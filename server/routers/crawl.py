"""Crawl endpoints (PROJECTBRIEF §8).

This router is the thin IPC layer: it translates HTTP requests into Crawl4AI
calls and tracks each crawl as a job. Crawl4AI is imported lazily inside the
worker so the server can start and pass a standalone smoke test even when
Crawl4AI is not yet installed.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from job_manager import JobContext, JobManager
from models import (
    ContentFilterType,
    CrawlOptions,
    DeepCrawlRequest,
    DeepCrawlStrategy,
    ExtractionType,
    JobCreatedResponse,
    JobResultResponse,
    JobStatusResponse,
    LLMProviderId,
    PageResult,
    SingleCrawlRequest,
)

logger = logging.getLogger("app4crawl.crawl")

router = APIRouter(prefix="/crawl", tags=["crawl"])


def _manager(request: Request) -> JobManager:
    """Fetch the process-wide job manager from application state."""
    return request.app.state.job_manager


# --------------------------------------------------------------------------- #
# Crawl4AI translation helpers
# --------------------------------------------------------------------------- #
def _require_crawler():
    """Import and return Crawl4AI's ``AsyncWebCrawler``.

    Raises ``RuntimeError`` with a user-facing message if Crawl4AI is not
    installed, so callers surface a clear error instead of a bare ImportError.
    """
    try:
        from crawl4ai import AsyncWebCrawler
    except ImportError as exc:  # pragma: no cover - depends on runtime env
        raise RuntimeError(
            "Crawl4AI is not installed in the active environment. "
            "Run the App4Crawl setup flow to install it."
        ) from exc
    return AsyncWebCrawler


def _provider_string(provider: LLMProviderId, model: str) -> str:
    """Build Crawl4AI's ``provider/model`` identifier."""
    return f"{provider.value}/{model}"


def _build_run_config(options: CrawlOptions, deep: Optional[DeepCrawlRequest] = None):
    """Translate :class:`CrawlOptions` into a Crawl4AI ``CrawlerRunConfig``.

    Imported lazily; raises ``RuntimeError`` with a clear message if Crawl4AI
    is not installed.
    """
    try:
        from crawl4ai import CacheMode, CrawlerRunConfig
        from crawl4ai.content_filter_strategy import (
            BM25ContentFilter,
            PruningContentFilter,
        )
        from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator
    except ImportError as exc:  # pragma: no cover - depends on runtime env
        raise RuntimeError(
            "Crawl4AI is not installed in the active environment. "
            "Run the App4Crawl setup flow to install it."
        ) from exc

    # Content filter → markdown generator.
    content_filter = None
    cf = options.content_filter
    if cf.type is ContentFilterType.pruning:
        content_filter = PruningContentFilter(threshold=cf.threshold)
    elif cf.type is ContentFilterType.bm25 and cf.query:
        content_filter = BM25ContentFilter(user_query=cf.query)

    md_generator = DefaultMarkdownGenerator(content_filter=content_filter)

    config_kwargs: dict[str, Any] = {
        "markdown_generator": md_generator,
        "cache_mode": CacheMode.BYPASS if options.bypass_cache else CacheMode.ENABLED,
    }

    # LLM extraction.
    if options.extraction is not None:
        config_kwargs["extraction_strategy"] = _build_extraction_strategy(options)

    # Deep crawl strategy.
    if deep is not None:
        config_kwargs["deep_crawl_strategy"] = _build_deep_strategy(deep)

    return CrawlerRunConfig(**config_kwargs)


def _build_extraction_strategy(options: CrawlOptions):
    """Build a Crawl4AI ``LLMExtractionStrategy`` from request options."""
    from crawl4ai import LLMConfig
    from crawl4ai.extraction_strategy import LLMExtractionStrategy

    extraction = options.extraction
    assert extraction is not None  # guarded by caller
    llm = extraction.llm

    llm_config = LLMConfig(
        provider=_provider_string(llm.provider, llm.model),
        api_token=llm.api_key,
        base_url=llm.base_url,
    )

    if extraction.type is ExtractionType.schema:
        return LLMExtractionStrategy(
            llm_config=llm_config,
            schema=extraction.schema_definition,
            extraction_type="schema",
        )
    return LLMExtractionStrategy(
        llm_config=llm_config,
        instruction=extraction.instruction or "",
        extraction_type="block",
    )


def _build_deep_strategy(deep: DeepCrawlRequest):
    """Build a BFS/DFS deep-crawl strategy."""
    from crawl4ai.deep_crawling import (
        BFSDeepCrawlStrategy,
        DFSDeepCrawlStrategy,
    )

    cls = (
        BFSDeepCrawlStrategy
        if deep.strategy is DeepCrawlStrategy.bfs
        else DFSDeepCrawlStrategy
    )
    return cls(max_depth=deep.max_depth, max_pages=deep.max_pages)


def _page_result_from(result: Any, options: CrawlOptions) -> PageResult:
    """Convert a Crawl4AI result object into a :class:`PageResult`."""
    markdown_obj = getattr(result, "markdown", None)
    raw_markdown = None
    fit_markdown = None
    if isinstance(markdown_obj, str):
        raw_markdown = markdown_obj
    elif markdown_obj is not None:
        raw_markdown = getattr(markdown_obj, "raw_markdown", None)
        fit_markdown = getattr(markdown_obj, "fit_markdown", None)

    extracted = getattr(result, "extracted_content", None)
    if isinstance(extracted, str):
        try:
            extracted = json.loads(extracted)
        except (ValueError, TypeError):
            pass

    metadata = getattr(result, "metadata", None)
    title = metadata.get("title") if isinstance(metadata, dict) else None

    return PageResult(
        url=getattr(result, "url", ""),
        success=bool(getattr(result, "success", False)),
        title=title,
        status_code=getattr(result, "status_code", None),
        markdown=raw_markdown,
        fit_markdown=fit_markdown if options.include_fit_markdown else None,
        raw_html=getattr(result, "html", None) if options.include_raw_html else None,
        extracted_content=extracted,
        error=getattr(result, "error_message", None) or None,
    )


# --------------------------------------------------------------------------- #
# Workers
# --------------------------------------------------------------------------- #
def _make_single_worker(req: SingleCrawlRequest):
    """Create a worker coroutine for a single-URL crawl."""

    async def worker(ctx: JobContext) -> None:
        AsyncWebCrawler = _require_crawler()

        await ctx.progress(f"Starting crawl of {req.url}")
        run_config = _build_run_config(req.options)
        async with AsyncWebCrawler() as crawler:
            ctx.raise_if_cancelled()
            result = await crawler.arun(url=req.url, config=run_config)
            ctx.raise_if_cancelled()
            await ctx.add_result(_page_result_from(result, req.options))
        await ctx.progress("Crawl complete")

    return worker


def _make_deep_worker(req: DeepCrawlRequest):
    """Create a worker coroutine for a deep crawl."""

    async def worker(ctx: JobContext) -> None:
        AsyncWebCrawler = _require_crawler()

        await ctx.progress(
            f"Starting {req.strategy.value.upper()} deep crawl of {req.url}",
            max_depth=req.max_depth,
            max_pages=req.max_pages,
        )
        run_config = _build_run_config(req.options, deep=req)
        async with AsyncWebCrawler() as crawler:
            ctx.raise_if_cancelled()
            results = await crawler.arun(url=req.url, config=run_config)
            # Deep crawls return a list; a single result otherwise.
            if not isinstance(results, list):
                results = [results]
            for result in results:
                ctx.raise_if_cancelled()
                await ctx.add_result(_page_result_from(result, req.options))
        await ctx.progress("Deep crawl complete")

    return worker


# --------------------------------------------------------------------------- #
# Routes
# --------------------------------------------------------------------------- #
@router.post("/single", response_model=JobCreatedResponse, status_code=202)
async def crawl_single(req: SingleCrawlRequest, request: Request) -> JobCreatedResponse:
    """Start a single-URL crawl and return its job id."""
    manager = _manager(request)
    job = manager.create()
    manager.start(job, _make_single_worker(req))
    return JobCreatedResponse(job_id=job.id, status=job.status)


@router.post("/deep", response_model=JobCreatedResponse, status_code=202)
async def crawl_deep(req: DeepCrawlRequest, request: Request) -> JobCreatedResponse:
    """Start a deep crawl and return its job id."""
    manager = _manager(request)
    job = manager.create()
    manager.start(job, _make_deep_worker(req))
    return JobCreatedResponse(job_id=job.id, status=job.status)


@router.get("/{job_id}/status", response_model=JobStatusResponse)
async def job_status(job_id: str, request: Request) -> JobStatusResponse:
    """Poll the status of a crawl job."""
    job = _manager(request).get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Unknown job id")
    return JobStatusResponse(
        job_id=job.id,
        status=job.status,
        created_at=job.created_at,
        updated_at=job.updated_at,
        pages_crawled=job.pages_crawled,
        error=job.error,
    )


@router.get("/{job_id}/result", response_model=JobResultResponse)
async def job_result(job_id: str, request: Request) -> JobResultResponse:
    """Fetch the results of a crawl job."""
    job = _manager(request).get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Unknown job id")
    return JobResultResponse(
        job_id=job.id,
        status=job.status,
        results=job.results,
        error=job.error,
    )


@router.get("/{job_id}/stream")
async def job_stream(job_id: str, request: Request) -> StreamingResponse:
    """Stream live job events via Server-Sent Events."""
    manager = _manager(request)
    job = manager.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Unknown job id")

    async def event_generator():
        async for item in manager.subscribe(job):
            event = item["event"]
            data = json.dumps(item["data"])
            yield f"event: {event}\ndata: {data}\n\n"

    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    }
    return StreamingResponse(
        event_generator(), media_type="text/event-stream", headers=headers
    )


@router.delete("/{job_id}", status_code=200)
async def cancel_job(job_id: str, request: Request) -> dict[str, str]:
    """Cancel a running crawl."""
    cancelled = await _manager(request).cancel(job_id)
    if not cancelled:
        raise HTTPException(
            status_code=404, detail="Unknown job id or job already finished"
        )
    return {"job_id": job_id, "status": "cancelling"}
