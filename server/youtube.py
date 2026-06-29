"""YouTube transcript support for App4Crawl.

When a crawl target is a YouTube video, App4Crawl fetches the video's caption
track (via ``youtube-transcript-api``) and returns it as Markdown instead of
scraping the page DOM. No API key required.
"""

from __future__ import annotations

import html as html_lib
import json
import re
import urllib.parse
import urllib.request
from typing import Optional

from models import PageResult

#: Browser-like User-Agent so YouTube doesn't gate title lookups as a bot.
_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
)

#: Preferred caption languages, in order, before falling back to any available.
PREFERRED_LANGUAGES = ["en", "en-US", "en-GB"]

#: Approximate character length per output paragraph.
_PARAGRAPH_TARGET = 500


class YouTubeError(Exception):
    """Raised when a transcript cannot be produced, with a user-facing message."""


def is_youtube_url(url: str) -> bool:
    """Whether ``url`` points at a YouTube video."""
    return video_id_from_url(url) is not None


def video_id_from_url(url: str) -> Optional[str]:
    """Extract the 11-character video id from common YouTube URL forms."""
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return None
    host = (parsed.hostname or "").lower().removeprefix("www.")

    if host == "youtu.be":
        candidate = parsed.path.lstrip("/").split("/")[0]
        return candidate or None

    if host in {"youtube.com", "m.youtube.com", "music.youtube.com"}:
        if parsed.path == "/watch":
            query = urllib.parse.parse_qs(parsed.query)
            values = query.get("v")
            return values[0] if values else None
        for prefix in ("/shorts/", "/embed/", "/v/", "/live/"):
            if parsed.path.startswith(prefix):
                candidate = parsed.path[len(prefix):].split("/")[0]
                return candidate or None
    return None


def build_page_result(url: str) -> PageResult:
    """Fetch a YouTube transcript and return it as a :class:`PageResult`.

    Runs synchronously (network + parsing); call it from a worker thread.
    Raises :class:`YouTubeError` with a user-facing message on failure.
    """
    video_id = video_id_from_url(url)
    if not video_id:
        raise YouTubeError("That doesn't look like a YouTube video URL.")

    segments = _fetch_segments(video_id)
    title = _fetch_title(video_id) or f"YouTube transcript ({video_id})"
    markdown = _format_markdown(title, url, segments)
    timestamped = [
        {"start": round(float(seg.get("start", 0.0)), 2), "text": seg["text"]}
        for seg in segments
        if seg.get("text", "").strip()
    ]

    return PageResult(
        url=url,
        success=True,
        title=title,
        status_code=200,
        markdown=markdown,
        fit_markdown=markdown,
        raw_html=None,
        extracted_content=timestamped,
        error=None,
    )


def _fetch_segments(video_id: str) -> list[dict]:
    """Return raw transcript segments (``{text, start, duration}``)."""
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        from youtube_transcript_api import (
            NoTranscriptFound,
            TranscriptsDisabled,
            VideoUnavailable,
        )
        from youtube_transcript_api import (
            IpBlocked,
            RequestBlocked,
        )
    except ImportError as exc:  # pragma: no cover - depends on runtime env
        raise YouTubeError(
            "YouTube transcript support isn't installed. In Settings → "
            "Environment, choose Reinstall / Update."
        ) from exc

    api = YouTubeTranscriptApi()
    try:
        try:
            fetched = api.fetch(video_id, languages=PREFERRED_LANGUAGES)
        except NoTranscriptFound:
            # Fall back to any available transcript (prefer human-made).
            transcripts = list(api.list(video_id))
            if not transcripts:
                raise
            chosen = next((t for t in transcripts if not t.is_generated), transcripts[0])
            fetched = chosen.fetch()
        return fetched.to_raw_data()
    except TranscriptsDisabled as exc:
        raise YouTubeError("This video has transcripts/captions disabled.") from exc
    except NoTranscriptFound as exc:
        raise YouTubeError("No transcript is available for this video.") from exc
    except VideoUnavailable as exc:
        raise YouTubeError("This video is unavailable.") from exc
    except (IpBlocked, RequestBlocked) as exc:
        raise YouTubeError(
            "YouTube is temporarily blocking transcript requests. Try again later."
        ) from exc
    except Exception as exc:  # noqa: BLE001 - surface any retrieval failure
        raise YouTubeError(f"Could not fetch the transcript: {exc}") from exc


def _fetch_title(video_id: str) -> Optional[str]:
    """Best-effort video title: oEmbed first, then the page ``<title>``.

    Uses the canonical watch URL (oEmbed doesn't reliably accept ``youtu.be``
    share links with tracking params).
    """
    watch_url = f"https://www.youtube.com/watch?v={video_id}"
    return _oembed_title(watch_url) or _page_title(watch_url)


def _oembed_title(watch_url: str) -> Optional[str]:
    """Title via YouTube's public oEmbed endpoint (no key)."""
    endpoint = "https://www.youtube.com/oembed?" + urllib.parse.urlencode(
        {"url": watch_url, "format": "json"}
    )
    try:
        request = urllib.request.Request(endpoint, headers={"User-Agent": _USER_AGENT})
        with urllib.request.urlopen(request, timeout=10) as response:
            data = json.load(response)
        title = data.get("title")
        return title.strip() if isinstance(title, str) and title.strip() else None
    except Exception:  # noqa: BLE001 - title is best-effort
        return None


def _page_title(watch_url: str) -> Optional[str]:
    """Fallback: scrape the watch page's ``<title>`` (minus the ' - YouTube')."""
    try:
        request = urllib.request.Request(watch_url, headers={"User-Agent": _USER_AGENT})
        with urllib.request.urlopen(request, timeout=10) as response:
            html = response.read(300_000).decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - title is best-effort
        return None
    match = re.search(r"<title>(.*?)</title>", html, re.IGNORECASE | re.DOTALL)
    if not match:
        return None
    title = html_lib.unescape(match.group(1)).strip()
    if title.endswith(" - YouTube"):
        title = title[: -len(" - YouTube")].strip()
    return title or None


def _format_markdown(title: str, url: str, segments: list[dict]) -> str:
    """Render transcript segments into readable Markdown paragraphs."""
    paragraphs: list[str] = []
    current: list[str] = []
    length = 0
    for segment in segments:
        text = " ".join(segment.get("text", "").split())
        if not text:
            continue
        current.append(text)
        length += len(text) + 1
        if length >= _PARAGRAPH_TARGET:
            paragraphs.append(" ".join(current))
            current = []
            length = 0
    if current:
        paragraphs.append(" ".join(current))

    body = "\n\n".join(paragraphs) if paragraphs else "_No transcript text found._"
    return f"# {title}\n\n[{url}]({url})\n\n{body}\n"
