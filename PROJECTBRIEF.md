# App4Crawl — Project Brief

> **For Claude Code:** This document is the authoritative project brief. Follow it as the primary instruction set. Where instructions are silent, apply best practices and log open questions in `OPENQUESTIONS.md`.

---

## 1. Project Overview

**App name:** App4Crawl  
**Platform:** macOS (native)  
**Purpose:** A clean, minimal native macOS GUI that makes the full feature set of [Crawl4AI](https://github.com/unclecode/crawl4ai) visually accessible to non-technical and technical users alike — without requiring command-line interaction or manual config file editing.  
**Target audience:** General public. Assume no Python knowledge. The app manages its own environment.  
**Distribution:** Direct (`.dmg`), not Mac App Store initially.

---

## 2. Architecture

```
App4Crawl.app (SwiftUI)
    ↕ localhost HTTP (127.0.0.1:PORT, dynamic)
app4crawl-server (FastAPI, Python)
    ↕
Crawl4AI (pip package, managed venv)
    ↕
Playwright + Chromium (managed by Crawl4AI)
```

### Components

| Component | Language | Role |
|---|---|---|
| `App4Crawl.app` | Swift / SwiftUI | Native macOS GUI |
| `server/main.py` | Python / FastAPI | Thin IPC layer exposing Crawl4AI |
| `server/requirements.txt` | — | `fastapi`, `uvicorn`, `crawl4ai` |
| Crawl4AI | Python (external) | All crawling and extraction logic |

### IPC
- The SwiftUI app launches the FastAPI server as a subprocess on startup.
- Communication over `127.0.0.1` on a dynamically chosen open port (avoids conflicts).
- The app shuts the server down cleanly on quit.
- All API responses are JSON. Streaming results use Server-Sent Events (SSE).

---

## 3. Python Environment Management

### Detection order (on first launch and on each startup)
1. Check for an existing Crawl4AI installation:
   - Look for an App4Crawl-managed venv at `~/.app4crawl/venv/`
   - If not found, check system Python (`python3 -c "import crawl4ai"`)
2. If found, use it.
3. If not found, offer the user an **Install** flow (see §4).

### Managed venv location
```
~/.app4crawl/
    venv/          # Isolated Python virtualenv
    config/        # App settings (non-sensitive)
    logs/          # Server and crawl logs
```

### Python version requirement
- Minimum: Python 3.10
- The app checks the system Python version before creating a venv.
- If Python 3.10+ is not found, display a clear error with a link to [python.org](https://www.python.org/downloads/) and instructions to install via Homebrew (`brew install python`).

---

## 4. First-Launch Install Flow

Present a clean onboarding screen (not a terminal) that walks the user through:

1. **Environment check** — detect Python, show version found or not found.
2. **Install Crawl4AI** — button triggers:
   ```bash
   python3 -m venv ~/.app4crawl/venv
   ~/.app4crawl/venv/bin/pip install -U crawl4ai
   ~/.app4crawl/venv/bin/crawl4ai-setup  # installs Playwright + Chromium
   ```
3. **Progress display** — show live output in a log view within the onboarding screen. Do not hide this behind a spinner only — users need to see that something is happening.
4. **Verification** — run `crawl4ai-doctor` and show result.
5. **Complete** — transition to the main app UI.

If Crawl4AI is already installed (detected in step 3 of §3), skip this flow and go directly to the main UI. Show a subtle status indicator confirming which environment is active.

---

## 5. Feature Scope

### v1.0 (Initial Release)

| Feature | Details |
|---|---|
| Single URL crawl | URL input, run crawl, view output |
| Deep crawl | BFS and DFS strategies, configurable depth and page limit |
| Output formats | Markdown (clean + fit), raw HTML, extracted JSON |
| Content filtering | Pruning filter (threshold), BM25 filter (query-based) |
| LLM extraction | Schema-based and instruction-based; provider + model selection |
| API key management | GUI-based; stored in macOS Keychain; never written to disk |
| Result viewer | Markdown-rendered output, JSON tree, raw HTML tab |
| Export | Save results to file (`.md`, `.json`, `.html`) |
| Crawl history | Local log of past crawls with re-run capability |

### Post-v1 (do not build now, but design for extensibility)
- Proxy configuration
- Session management and browser profiles
- Custom JavaScript hooks
- Adaptive crawling
- Batch URL list processing
- Scheduled crawls

---

## 6. UI Design Direction

**Aesthetic:** Clean and minimal. Inspired by macOS-native apps (think Things 3, Retcon, or Apple's own apps). No browser-like chrome. No Electron feel.

**Principles:**
- Every Crawl4AI feature is reachable within 2 clicks from the main screen.
- Labels and controls use plain English, not Crawl4AI's internal parameter names (e.g., "Remove noise from content" not "PruningContentFilter threshold").
- Progressive disclosure: show simple options by default, reveal advanced options via an "Advanced" toggle or expandable section — never hide power features entirely.
- No modal dialogs for settings — use a sidebar or inspector panel.
- Native macOS conventions: keyboard shortcuts, right-click context menus, drag-and-drop where natural.

**Layout (suggested):**
```
┌─────────────────────────────────────────────────┐
│ Toolbar: [New Crawl] [History] [Settings]        │
├────────────┬────────────────────────────────────┤
│            │                                    │
│  Sidebar   │   Main Content Area                │
│  (History/ │   (Crawl config or Result viewer)  │
│   Sessions)│                                    │
│            │                                    │
└────────────┴────────────────────────────────────┘
```

**Settings / Preferences (⌘,):**
- API Keys panel (Keychain-backed): add/edit/delete keys per provider
- Environment panel: shows active Python/Crawl4AI version, option to reinstall or update
- Appearance: system / light / dark

---

## 7. API Key Management

- Supported providers (v1): OpenAI, Anthropic, Gemini, Ollama (local, no key needed), custom (base URL + key)
- Storage: macOS Keychain via `SecItemAdd` / `SecItemCopyMatching`. Never `UserDefaults`, plist, or any file on disk.
- The Swift app reads keys from Keychain and passes them to the FastAPI server as HTTP headers or request body fields — never as environment variables written to disk.
- The FastAPI server receives keys per-request and passes them to Crawl4AI's `LLMConfig`. Keys are never persisted by the server.

---

## 8. FastAPI Server (`server/`)

### Endpoints (v1)

| Method | Path | Description |
|---|---|---|
| `GET` | `/health` | Liveness check; returns Crawl4AI version |
| `POST` | `/crawl/single` | Single URL crawl |
| `POST` | `/crawl/deep` | Deep crawl with strategy config |
| `GET` | `/crawl/{job_id}/status` | Poll job status |
| `GET` | `/crawl/{job_id}/result` | Fetch result |
| `GET` | `/crawl/{job_id}/stream` | SSE stream for live output |
| `DELETE` | `/crawl/{job_id}` | Cancel a running crawl |
| `GET` | `/providers` | List supported LLM providers |

### Design rules for the server
- Thin: no business logic. Translate requests → Crawl4AI calls → return results.
- Async throughout (`asyncio`, `async def` endpoints).
- Each crawl runs as a tracked job with a UUID. Store job state in memory (dict); no database for v1.
- Server binds only to `127.0.0.1`, never `0.0.0.0`.
- Log to `~/.app4crawl/logs/server.log` with rotation.

---

## 9. Project Structure

```
App4Crawl/
├── App4Crawl.xcodeproj          # Xcode project
├── App4Crawl/                   # SwiftUI source
│   ├── App4CrawlApp.swift       # App entry point; manages server lifecycle
│   ├── Views/
│   │   ├── OnboardingView.swift
│   │   ├── MainView.swift
│   │   ├── CrawlConfigView.swift
│   │   ├── ResultView.swift
│   │   ├── HistoryView.swift
│   │   └── SettingsView.swift
│   ├── Models/
│   │   ├── CrawlJob.swift
│   │   ├── CrawlConfig.swift
│   │   └── LLMProvider.swift
│   ├── Services/
│   │   ├── ServerManager.swift  # Subprocess lifecycle
│   │   ├── CrawlAPIClient.swift # HTTP client
│   │   ├── KeychainService.swift
│   │   └── EnvironmentChecker.swift
│   └── Resources/
│       └── Assets.xcassets
├── server/                      # Python FastAPI backend
│   ├── main.py
│   ├── routers/
│   │   ├── crawl.py
│   │   └── health.py
│   ├── models.py                # Pydantic request/response models
│   ├── job_manager.py           # In-memory job tracking
│   └── requirements.txt
├── scripts/
│   ├── setup_env.sh             # Used by onboarding flow
│   └── check_env.sh
├── README.md
├── INSTRUCTIONS.md
├── OPENQUESTIONS.md
├── CHANGELOG.md
└── PROJECTBRIEF.md              # This file
```

---

## 10. Supporting Documents

Claude Code must create and maintain the following documents throughout the build. Create them at project initialization with the structure below.

### `README.md`
```markdown
# App4Crawl

A native macOS GUI for Crawl4AI — the open-source LLM-friendly web crawler.

## What it does
## Requirements
## Installation
## Building from source
## Architecture overview
## Contributing
## License
```

### `INSTRUCTIONS.md`
```markdown
# App4Crawl — User Guide

## System Requirements
## Installation
## First Launch
## How to crawl a URL
## How to run a deep crawl
## Using LLM extraction
## Managing API keys
## Exporting results
## Troubleshooting
## FAQ
```

### `OPENQUESTIONS.md`
```markdown
# Open Questions

Questions that arise during development and require decisions before proceeding.
Log here rather than making silent assumptions.

| # | Question | Context | Status |
|---|---|---|---|
| 1 | (initial entry) | | Open |
```

### `CHANGELOG.md`
Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:
```markdown
# Changelog

All notable changes to App4Crawl will be documented here.
Format: Keep a Changelog (https://keepachangelog.com/en/1.0.0/)
Versioning: Semantic Versioning (https://semver.org/)

## [Unreleased]

## [0.1.0] - YYYY-MM-DD
### Added
- Initial project scaffold
```

---

## 11. Version Management

### Scheme: Semantic Versioning (SemVer)
```
MAJOR.MINOR.PATCH
  │     │     └── Bug fixes, no API or feature changes
  │     └──────── New features, backward compatible
  └────────────── Breaking changes
```

- **0.x.x** = pre-release / development (current phase)
- **1.0.0** = first public release
- **Never ship 0.x.x to the public** without a clear pre-release label

### Git branching
```
main          ← stable, tagged releases only
develop       ← integration branch
feature/*     ← individual features
fix/*         ← bug fixes
release/*     ← release preparation
```

### Tagging
- Every release gets a Git tag: `git tag -a v0.1.0 -m "Initial scaffold"`
- Tags must match the version in:
  - `CHANGELOG.md`
  - Xcode project `CFBundleShortVersionString`
  - `server/main.py` (`APP_VERSION` constant)

### Release checklist (Claude Code should prompt for this before tagging)
- [ ] All tests pass
- [ ] `CHANGELOG.md` updated with date and release notes
- [ ] Version bumped in all three locations above
- [ ] `OPENQUESTIONS.md` reviewed — no blockers open
- [ ] `README.md` accurate for this release

---

## 12. Build Sequence for Claude Code

Execute in this order. Do not proceed to the next phase without completing the current one.

**Phase 1 — Scaffold**
- Create directory structure per §9
- Initialize Xcode project (SwiftUI, macOS 14+, Swift 5.9+)
- Create all supporting documents (§10) with placeholder content
- Initialize Git repo, create `develop` branch, make initial commit tagged `v0.0.1`

**Phase 2 — Python backend**
- Build `server/main.py` with all v1 endpoints (§8)
- Build `server/models.py` with Pydantic models for all request/response types
- Build `server/job_manager.py`
- Write `server/requirements.txt`
- Verify server runs standalone: `uvicorn main:app --host 127.0.0.1`

**Phase 3 — Environment management (Swift)**
- `EnvironmentChecker.swift`: detect Python, detect Crawl4AI
- `ServerManager.swift`: launch/monitor/terminate FastAPI subprocess
- Onboarding flow: `OnboardingView.swift` with install progress

**Phase 4 — Core UI**
- `MainView.swift` with sidebar + content area layout
- `CrawlConfigView.swift`: single URL and deep crawl configuration
- `CrawlAPIClient.swift`: HTTP client connecting to FastAPI
- `ResultView.swift`: Markdown, JSON, and HTML tabs

**Phase 5 — API key management**
- `KeychainService.swift`
- `SettingsView.swift` API Keys panel
- Wire keys through `CrawlAPIClient` → FastAPI → Crawl4AI `LLMConfig`

**Phase 6 — History and export**
- `HistoryView.swift` with local crawl log
- Export to `.md`, `.json`, `.html`

**Phase 7 — Polish and release prep**
- App icon and assets
- Keyboard shortcuts
- Error handling and empty states
- Update all docs for v1.0.0
- Tag `v1.0.0`

---

## 13. Conventions for Claude Code

- Log any architectural decision that deviates from this brief in `OPENQUESTIONS.md` before implementing.
- Every commit message follows Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`.
- No hardcoded secrets, ports, or paths. Use constants files.
- Swift: follow Swift API Design Guidelines. No force unwraps in production paths.
- Python: PEP 8, type hints on all function signatures, docstrings on all public functions.
- If a phase reveals that a subsequent phase needs redesign, stop and surface the question rather than proceeding with a guess.
