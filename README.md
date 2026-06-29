# App4Crawl

A native macOS GUI for Crawl4AI — the open-source LLM-friendly web crawler.

> **Status:** `1.1.0` — builds and runs on macOS 14+. For distribution to other
> users, the app still needs code signing + notarization (see `OPENQUESTIONS.md`).

## What it does

App4Crawl puts the full feature set of [Crawl4AI](https://github.com/unclecode/crawl4ai)
behind a clean, minimal native macOS interface. No command line, no manual config
files, no Python knowledge required — the app manages its own Python environment and
exposes crawling, content filtering, and LLM extraction through a visual UI.

- Single-URL and deep crawls (BFS/DFS, configurable depth and page limit)
- Output as clean Markdown, raw HTML, and extracted JSON
- Content filtering (noise pruning and query-based BM25)
- LLM extraction (schema- or instruction-based) across OpenAI, Anthropic,
  Gemini, and Ollama
- API keys stored in the macOS Keychain, never on disk
- Result viewer with Markdown / JSON-tree / HTML tabs and export to
  `.md` / `.json` / `.html`
- YouTube transcripts: paste a video URL to get the transcript as Markdown
- Local crawl history with one-click re-run
- Guided first-launch setup that installs the Crawl4AI environment for you

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10+ (the app can guide installation via Homebrew or python.org)
- Internet connection for the first-launch install of Crawl4AI + Chromium

## Installation

Download the latest `.dmg` from the releases page, drag **App4Crawl** to your
Applications folder, and launch it. On first launch the app walks you through
installing the Crawl4AI environment (see the in-app onboarding flow).

## Building from source

```bash
git clone https://github.com/johnjanney/app4crawl.git
cd app4crawl
open App4Crawl.xcodeproj
```

Build and run the `App4Crawl` scheme in Xcode (macOS 14+ deployment target,
Swift 5.9+). The Python backend lives in `server/` and is launched automatically
by the app as a subprocess; to run it standalone for development:

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 127.0.0.1 --port 8000
```

<img width="2024" height="1554" alt="SCR-20260628-txxe" src="https://github.com/user-attachments/assets/3ad687f9-7ae9-4903-9865-a41144e36a41" />


## Architecture overview

```
App4Crawl.app (SwiftUI)
    ↕ localhost HTTP (127.0.0.1:PORT, dynamic)
app4crawl-server (FastAPI, Python)
    ↕
Crawl4AI (pip package, managed venv)
    ↕
Playwright + Chromium (managed by Crawl4AI)
```

The SwiftUI app launches the FastAPI server as a subprocess on a dynamically
chosen local port, communicates over `127.0.0.1` with JSON and Server-Sent
Events, and shuts the server down cleanly on quit. See `PROJECTBRIEF.md` for the
full architecture and design rationale.

## Contributing

This project follows [Conventional Commits](https://www.conventionalcommits.org/)
and [Semantic Versioning](https://semver.org/). Development happens on the
`develop` branch; `main` holds tagged releases only. Open questions and pending
design decisions are tracked in `OPENQUESTIONS.md`.

## License

Released under the [MIT License](LICENSE).
