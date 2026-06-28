"""Health / liveness endpoint (PROJECTBRIEF §8)."""

from __future__ import annotations

import importlib.metadata
import logging
from typing import Optional

from fastapi import APIRouter

from config import APP_VERSION
from models import HealthResponse

logger = logging.getLogger("app4crawl.health")

router = APIRouter(tags=["health"])


def detect_crawl4ai_version() -> Optional[str]:
    """Return the installed Crawl4AI version, or ``None`` if unavailable.

    Uses package metadata to avoid importing the (heavy) package just for a
    liveness check.
    """
    try:
        return importlib.metadata.version("crawl4ai")
    except importlib.metadata.PackageNotFoundError:
        return None


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Liveness check; reports the server and Crawl4AI versions."""
    version = detect_crawl4ai_version()
    return HealthResponse(
        status="ok",
        app_version=APP_VERSION,
        crawl4ai_version=version,
        crawl4ai_available=version is not None,
    )
