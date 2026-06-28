"""In-memory crawl job tracking for the App4Crawl server.

Each crawl runs as a tracked job identified by a UUID. Job state lives in a
process-local dict — no database for v1 (PROJECTBRIEF §8). The actual crawling
logic is supplied by the caller as a worker coroutine, keeping this module free
of any Crawl4AI dependency (thin server, separation of concerns).
"""

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Awaitable, Callable, Optional

from models import JobStatus, PageResult

logger = logging.getLogger("app4crawl.jobs")


class JobCancelled(Exception):
    """Raised inside a worker when the job has been cancelled."""


@dataclass
class Job:
    """State for a single crawl job."""

    id: str
    status: JobStatus = JobStatus.queued
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    pages_crawled: int = 0
    error: Optional[str] = None
    results: list[PageResult] = field(default_factory=list)

    # Runtime-only fields (not serialized).
    _task: Optional[asyncio.Task] = field(default=None, repr=False)
    _cancel_event: asyncio.Event = field(default_factory=asyncio.Event, repr=False)
    _subscribers: list[asyncio.Queue] = field(default_factory=list, repr=False)
    _done: asyncio.Event = field(default_factory=asyncio.Event, repr=False)

    def touch(self) -> None:
        """Update the last-modified timestamp."""
        self.updated_at = time.time()


class JobContext:
    """Handle passed to a worker coroutine for reporting progress.

    Workers use this to append results, update progress, emit SSE events, and
    cooperatively check for cancellation. It deliberately exposes nothing about
    the underlying storage.
    """

    def __init__(self, job: Job, manager: "JobManager") -> None:
        self._job = job
        self._manager = manager

    @property
    def job_id(self) -> str:
        """The owning job's UUID."""
        return self._job.id

    def is_cancelled(self) -> bool:
        """Whether cancellation has been requested for this job."""
        return self._job._cancel_event.is_set()

    def raise_if_cancelled(self) -> None:
        """Raise :class:`JobCancelled` if cancellation has been requested."""
        if self.is_cancelled():
            raise JobCancelled

    async def emit(self, event: str, data: dict[str, Any]) -> None:
        """Publish an SSE event to all subscribers of this job."""
        await self._manager.publish(self._job, event, data)

    async def add_result(self, page: PageResult) -> None:
        """Append a page result and emit a ``result`` event."""
        self._job.results.append(page)
        self._job.pages_crawled = len(self._job.results)
        self._job.touch()
        await self.emit("result", page.model_dump())

    async def progress(self, message: str, **extra: Any) -> None:
        """Emit a ``progress`` event with a human-readable message."""
        await self.emit("progress", {"message": message, **extra})


# Worker signature: receives a JobContext, performs the crawl.
Worker = Callable[[JobContext], Awaitable[None]]


class JobManager:
    """Owns the lifecycle of all crawl jobs in this process."""

    def __init__(self) -> None:
        self._jobs: dict[str, Job] = {}
        self._lock = asyncio.Lock()

    def create(self) -> Job:
        """Create and register a new queued job."""
        job_id = str(uuid.uuid4())
        job = Job(id=job_id)
        self._jobs[job_id] = job
        logger.info("Created job %s", job_id)
        return job

    def get(self, job_id: str) -> Optional[Job]:
        """Return the job with ``job_id``, or ``None`` if unknown."""
        return self._jobs.get(job_id)

    def start(self, job: Job, worker: Worker) -> None:
        """Schedule ``worker`` to run for ``job`` as a background task."""
        job._task = asyncio.create_task(self._run(job, worker))

    async def _run(self, job: Job, worker: Worker) -> None:
        """Drive a worker through the job lifecycle, recording terminal state."""
        job.status = JobStatus.running
        job.touch()
        ctx = JobContext(job, self)
        await self.publish(job, "status", {"status": job.status.value})
        try:
            await worker(ctx)
            job.status = (
                JobStatus.cancelled if ctx.is_cancelled() else JobStatus.completed
            )
        except (JobCancelled, asyncio.CancelledError):
            job.status = JobStatus.cancelled
            logger.info("Job %s cancelled", job.id)
        except Exception as exc:  # noqa: BLE001 - report any worker failure
            job.status = JobStatus.failed
            job.error = str(exc)
            logger.exception("Job %s failed", job.id)
        finally:
            job.touch()
            await self.publish(job, "status", {"status": job.status.value})
            if job.error:
                await self.publish(job, "error", {"detail": job.error})
            await self.publish(job, "done", {"status": job.status.value})
            job._done.set()
            self._close_subscribers(job)

    async def cancel(self, job_id: str) -> bool:
        """Request cancellation of a running job.

        Returns ``True`` if the job exists and was running/queued, ``False``
        otherwise.
        """
        job = self._jobs.get(job_id)
        if job is None:
            return False
        if job.status in (JobStatus.completed, JobStatus.failed, JobStatus.cancelled):
            return False
        job._cancel_event.set()
        if job._task is not None:
            job._task.cancel()
        logger.info("Cancellation requested for job %s", job_id)
        return True

    # --------------------------------------------------------------------- #
    # SSE pub/sub
    # --------------------------------------------------------------------- #
    async def publish(self, job: Job, event: str, data: dict[str, Any]) -> None:
        """Fan an event out to all current subscribers of ``job``."""
        payload = {"event": event, "data": data}
        for queue in list(job._subscribers):
            await queue.put(payload)

    def _close_subscribers(self, job: Job) -> None:
        """Signal end-of-stream to all subscribers by enqueuing ``None``."""
        for queue in list(job._subscribers):
            queue.put_nowait(None)

    async def subscribe(self, job: Job) -> AsyncIterator[dict[str, Any]]:
        """Yield SSE events for ``job`` until the job completes.

        If the job is already finished, replays its terminal status and stops.
        """
        queue: asyncio.Queue = asyncio.Queue()
        job._subscribers.append(queue)
        try:
            # If already done, emit a final status and finish immediately.
            if job._done.is_set():
                yield {"event": "status", "data": {"status": job.status.value}}
                yield {"event": "done", "data": {"status": job.status.value}}
                return
            while True:
                item = await queue.get()
                if item is None:  # end-of-stream sentinel
                    break
                yield item
        finally:
            if queue in job._subscribers:
                job._subscribers.remove(queue)
