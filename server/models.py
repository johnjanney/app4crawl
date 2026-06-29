"""Pydantic request/response models for the App4Crawl FastAPI server.

These mirror the user-facing options exposed by the SwiftUI app and translate
into Crawl4AI configuration objects in the routers (PROJECTBRIEF §8). Field
names use plain, API-stable terms; the app maps friendly labels onto them.
"""

from __future__ import annotations

from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


# --------------------------------------------------------------------------- #
# Enums
# --------------------------------------------------------------------------- #
class JobStatus(str, Enum):
    """Lifecycle states of a crawl job."""

    queued = "queued"
    running = "running"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"


class DeepCrawlStrategy(str, Enum):
    """Traversal strategy for deep crawls."""

    bfs = "bfs"
    dfs = "dfs"


class ContentFilterType(str, Enum):
    """Supported content filters (PROJECTBRIEF §5)."""

    none = "none"
    pruning = "pruning"
    bm25 = "bm25"


class ExtractionType(str, Enum):
    """LLM extraction modes (PROJECTBRIEF §5)."""

    schema = "schema"
    instruction = "instruction"


class LLMProviderId(str, Enum):
    """LLM providers supported in v1 (PROJECTBRIEF §7)."""

    openai = "openai"
    anthropic = "anthropic"
    gemini = "gemini"
    ollama = "ollama"


# --------------------------------------------------------------------------- #
# Nested config models
# --------------------------------------------------------------------------- #
class ContentFilterConfig(BaseModel):
    """Configuration for content filtering applied to crawl output."""

    type: ContentFilterType = ContentFilterType.none
    #: Pruning threshold in [0, 1]; higher removes more "noise".
    threshold: float = Field(default=0.48, ge=0.0, le=1.0)
    #: Query string for BM25 relevance filtering.
    query: Optional[str] = None


class LLMConfigModel(BaseModel):
    """Per-request LLM configuration for extraction.

    The API key is supplied per request and never persisted by the server
    (PROJECTBRIEF §7).
    """

    provider: LLMProviderId
    model: str
    #: API key for the provider. Omitted for local providers (e.g. Ollama).
    api_key: Optional[str] = None
    #: Base URL for custom / self-hosted providers.
    base_url: Optional[str] = None


class ExtractionConfig(BaseModel):
    """LLM extraction configuration."""

    type: ExtractionType
    llm: LLMConfigModel
    #: JSON schema (as a dict) for schema-based extraction.
    schema_definition: Optional[dict[str, Any]] = None
    #: Natural-language instruction for instruction-based extraction.
    instruction: Optional[str] = None


# --------------------------------------------------------------------------- #
# Request models
# --------------------------------------------------------------------------- #
class CrawlOptions(BaseModel):
    """Options common to single and deep crawls."""

    #: Which output formats to compute/return.
    include_raw_html: bool = True
    include_fit_markdown: bool = True
    content_filter: ContentFilterConfig = Field(default_factory=ContentFilterConfig)
    extraction: Optional[ExtractionConfig] = None
    #: Bypass Crawl4AI's local cache for this request.
    bypass_cache: bool = False


class SingleCrawlRequest(BaseModel):
    """Request body for ``POST /crawl/single``."""

    url: str
    options: CrawlOptions = Field(default_factory=CrawlOptions)


class DeepCrawlRequest(BaseModel):
    """Request body for ``POST /crawl/deep``."""

    url: str
    strategy: DeepCrawlStrategy = DeepCrawlStrategy.bfs
    max_depth: int = Field(default=2, ge=1, le=10)
    max_pages: int = Field(default=10, ge=1, le=1000)
    options: CrawlOptions = Field(default_factory=CrawlOptions)


# --------------------------------------------------------------------------- #
# Response models
# --------------------------------------------------------------------------- #
class HealthResponse(BaseModel):
    """Response for ``GET /health``."""

    status: str = "ok"
    app_version: str
    crawl4ai_version: Optional[str] = None
    crawl4ai_available: bool = False


class JobCreatedResponse(BaseModel):
    """Returned when a crawl job is accepted."""

    job_id: str
    status: JobStatus


class JobStatusResponse(BaseModel):
    """Response for ``GET /crawl/{job_id}/status``."""

    job_id: str
    status: JobStatus
    created_at: float
    updated_at: float
    #: Number of pages crawled so far (deep crawls).
    pages_crawled: int = 0
    error: Optional[str] = None


class PageResult(BaseModel):
    """Result for a single crawled page."""

    url: str
    success: bool
    #: Page title from the crawled document's metadata, if available.
    title: Optional[str] = None
    status_code: Optional[int] = None
    markdown: Optional[str] = None
    fit_markdown: Optional[str] = None
    raw_html: Optional[str] = None
    extracted_content: Optional[Any] = None
    error: Optional[str] = None


class JobResultResponse(BaseModel):
    """Response for ``GET /crawl/{job_id}/result``."""

    job_id: str
    status: JobStatus
    results: list[PageResult] = Field(default_factory=list)
    error: Optional[str] = None


class ProviderInfo(BaseModel):
    """Describes a supported LLM provider for ``GET /providers``."""

    id: LLMProviderId
    display_name: str
    requires_api_key: bool
    #: Suggested model identifiers for this provider.
    suggested_models: list[str] = Field(default_factory=list)


class ProvidersResponse(BaseModel):
    """Response for ``GET /providers``."""

    providers: list[ProviderInfo]


class ErrorResponse(BaseModel):
    """Generic error payload."""

    detail: str
