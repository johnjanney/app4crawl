"""App4Crawl FastAPI server entry point.

A thin IPC layer that exposes Crawl4AI to the SwiftUI app over loopback HTTP
(PROJECTBRIEF §2, §8). Binds only to ``127.0.0.1``; the Swift app launches this
as a subprocess on a dynamically chosen port.

Run standalone for development::

    uvicorn main:app --host 127.0.0.1 --port 8000
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler

from fastapi import FastAPI

from config import (
    APP_VERSION,
    LOG_BACKUP_COUNT,
    LOG_MAX_BYTES,
    SERVER_LOG_FILE,
    ensure_directories,
)
from job_manager import JobManager
from models import LLMProviderId, ProviderInfo, ProvidersResponse
from routers import crawl, health

#: Application/server version constant (PROJECTBRIEF §11).
__version__ = APP_VERSION

logger = logging.getLogger("app4crawl")


def configure_logging() -> None:
    """Configure rotating file logging under ``~/.app4crawl/logs``.

    Falls back to console-only logging if the log directory cannot be created
    (PROJECTBRIEF §8).
    """
    handlers: list[logging.Handler] = [logging.StreamHandler()]
    try:
        ensure_directories()
        file_handler = RotatingFileHandler(
            SERVER_LOG_FILE,
            maxBytes=LOG_MAX_BYTES,
            backupCount=LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        handlers.append(file_handler)
    except OSError as exc:  # pragma: no cover - depends on filesystem
        logging.getLogger("app4crawl").warning(
            "Could not open log file %s: %s", SERVER_LOG_FILE, exc
        )

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=handlers,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize shared state on startup; clean up on shutdown."""
    configure_logging()
    app.state.job_manager = JobManager()
    logger.info("App4Crawl server %s starting", APP_VERSION)
    yield
    logger.info("App4Crawl server shutting down")


app = FastAPI(
    title="App4Crawl Server",
    version=APP_VERSION,
    summary="Thin FastAPI layer exposing Crawl4AI to the App4Crawl macOS app.",
    lifespan=lifespan,
)

app.include_router(health.router)
app.include_router(crawl.router)


#: Static provider catalog with suggested models (PROJECTBRIEF §7).
_PROVIDERS: list[ProviderInfo] = [
    ProviderInfo(
        id=LLMProviderId.openai,
        display_name="OpenAI",
        requires_api_key=True,
        suggested_models=["gpt-4o", "gpt-4o-mini"],
    ),
    ProviderInfo(
        id=LLMProviderId.anthropic,
        display_name="Anthropic",
        requires_api_key=True,
        suggested_models=["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022"],
    ),
    ProviderInfo(
        id=LLMProviderId.gemini,
        display_name="Gemini",
        requires_api_key=True,
        suggested_models=["gemini-1.5-pro", "gemini-1.5-flash"],
    ),
    ProviderInfo(
        id=LLMProviderId.ollama,
        display_name="Ollama (local)",
        requires_api_key=False,
        suggested_models=["llama3.3", "qwen2.5"],
    ),
]


@app.get("/providers", response_model=ProvidersResponse, tags=["providers"])
async def providers() -> ProvidersResponse:
    """List supported LLM providers (PROJECTBRIEF §8)."""
    return ProvidersResponse(providers=_PROVIDERS)
