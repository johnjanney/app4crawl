# Changelog

All notable changes to App4Crawl will be documented here.
Format: Keep a Changelog (https://keepachangelog.com/en/1.0.0/)
Versioning: Semantic Versioning (https://semver.org/)

## [Unreleased]

## [1.1.1] - 2026-06-29

### Fixed
- YouTube crawls are named after the video title again. The title lookup now
  queries oEmbed with the canonical watch URL (it rejected `youtu.be` share
  links carrying `?si=` tracking params) and falls back to the page `<title>`.
  Previously it fell back to `YouTube transcript (<id>)`.

### Added
- The "Connected" indicator shows the backend version (e.g. "Connected ·
  v1.1.1"), making it easy to confirm which server build the app is running.
- Server logs the YouTube routing decision for each single crawl (in
  `~/.app4crawl/logs/server.log`) to aid diagnosis.

## [1.1.0] - 2026-06-29

### Added
- YouTube transcripts: paste a YouTube video URL (watch, youtu.be, shorts, or
  embed) and App4Crawl returns the transcript as Markdown instead of scraping
  the page, with timestamped segments in the JSON tab. Uses
  `youtube-transcript-api`; no API key. The crawl is named after the video
  title. Existing installs: run Settings → Environment → Reinstall / Update to
  add the new dependency.

### Fixed
- Silence Swift concurrency warnings in `EnvironmentChecker.install()` by passing
  the install-log callback as a `@Sendable` closure literal instead of a method
  reference (no behavior change).

## [1.0.1] - 2026-06-29

### Removed
- The "Custom" LLM provider (base URL + key) is removed from the app and server.
  It never mapped correctly to Crawl4AI/LiteLLM and isn't needed. Supported
  providers are OpenAI, Anthropic, Gemini, and Ollama.

## [1.0.0] - 2026-06-29

First public release — a native macOS GUI for Crawl4AI. Licensed under MIT.

### Added
- Meaningful crawl names: auto-named from the page title (returned by the
  server) with an optional override field; used in the History list, the results
  header, and export filenames; history entries can be renamed.
- App icon, ⌘N (New Crawl) and ⌘R (Run) menu commands, a local-server status
  banner, and empty/error states throughout.
- Python FastAPI backend scaffold (`server/`): all v1 endpoints, Pydantic
  request/response models, and in-memory job manager.
- Environment management (Swift): `EnvironmentChecker` detects the Python /
  Crawl4AI environment (managed venv → system Python) and runs the managed-venv
  install flow with live progress; `ServerManager` allocates a dynamic loopback
  port, launches/health-checks/terminates the FastAPI subprocess; supporting
  `AppPaths` constants and a streaming `ProcessRunner`.
- Onboarding flow (`OnboardingView`) with environment check, install, live log,
  verification, and completion states; app wires server lifecycle to launch on
  ready and shut down cleanly on quit.
- Core UI (Swift): `CrawlAPIClient` (typed async client for all v1 endpoints
  plus an SSE event stream), Codable `APIModels`/`JSONValue` matching the server
  wire format, `CrawlConfigView` (single + deep crawl with progressive
  disclosure and plain-English labels), `ResultView` (rendered Markdown, a
  collapsible JSON tree, and raw HTML), and `MainView` with a sidebar/content
  layout, a `CrawlController` that runs and polls crawls, a multi-page result
  list, and a backend status indicator.
- API key management (Swift): `KeychainService` stores per-provider keys in the
  macOS Keychain (never on disk); Settings gains API Keys, Environment, and
  Appearance panels; LLM-extraction UI in the crawl config; keys are injected
  per-run from the Keychain into the request → server → Crawl4AI `LLMConfig`.
  Appearance preference (system/light/dark) applied app-wide.
- History & export (Swift): `HistoryStore` persists past crawls to
  ~/.app4crawl/config/history.json (capped, no secrets); `HistoryView` lists
  them with open-results, re-run, and delete; `ResultExporter` saves the
  selected page as `.md`, `.json`, or `.html` via a save panel.

### Fixed
- macOS build/run: main-actor-isolated `AppDelegate`; detect user-installed
  Python outside the GUI app's restricted PATH; verify Crawl4AI via package
  metadata (instead of a heavy import); bundle the FastAPI server (`server/`)
  into the app so the backend launches.

### Known limitations
- The custom LLM provider does not yet map correctly to Crawl4AI/LiteLLM
  (OPENQUESTIONS #10). OpenAI, Anthropic, Gemini, and Ollama work.

## [0.0.1] - 2026-06-28
### Added
- Initial project scaffold: directory structure, hand-authored Xcode project
  (SwiftUI, macOS 14+, Swift 5.9+) with placeholder views, models, and services.
- Supporting documents: `README.md`, `INSTRUCTIONS.md`, `OPENQUESTIONS.md`,
  `CHANGELOG.md`.
- Git repository initialized with `develop` integration branch.
