# Changelog

All notable changes to App4Crawl will be documented here.
Format: Keep a Changelog (https://keepachangelog.com/en/1.0.0/)
Versioning: Semantic Versioning (https://semver.org/)

## [Unreleased]

### Added
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

## [0.0.1] - 2026-06-28
### Added
- Initial project scaffold: directory structure, hand-authored Xcode project
  (SwiftUI, macOS 14+, Swift 5.9+) with placeholder views, models, and services.
- Supporting documents: `README.md`, `INSTRUCTIONS.md`, `OPENQUESTIONS.md`,
  `CHANGELOG.md`.
- Git repository initialized with `develop` integration branch.
