# Changelog

All notable changes to App4Crawl will be documented here.
Format: Keep a Changelog (https://keepachangelog.com/en/1.0.0/)
Versioning: Semantic Versioning (https://semver.org/)

## [Unreleased]

### Added
- Meaningful crawl names: each crawl is auto-named from the page title (server
  now returns it), with an optional "Name (optional)" field to override. The
  name is used in the History list, the results header, and the export filename.
  History entries can be renamed via the context menu.

## [1.0.0-rc.1] - 2026-06-29

Release candidate for 1.0.0. Numeric bundle version is 1.0.0; the `-rc.1`
qualifier marks this as a pre-release pending a build/run on macOS (the Swift
app has not yet been compiled — see OPENQUESTIONS).

### Added
- Polish: app icon, ⌘N (New Crawl) and ⌘R (Run) menu commands, a local-server
  status banner, and empty/error states throughout.
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

## [0.0.1] - 2026-06-28
### Added
- Initial project scaffold: directory structure, hand-authored Xcode project
  (SwiftUI, macOS 14+, Swift 5.9+) with placeholder views, models, and services.
- Supporting documents: `README.md`, `INSTRUCTIONS.md`, `OPENQUESTIONS.md`,
  `CHANGELOG.md`.
- Git repository initialized with `develop` integration branch.
