# Open Questions

Questions that arise during development and require decisions before proceeding.
Log here rather than making silent assumptions.

| # | Question | Context | Status |
|---|----------|---------|--------|
| 1 | Initial scaffold version tag: `v0.0.1` vs `v0.1.0`? | §12 Phase 1 says tag the initial commit `v0.0.1`, while §10 (CHANGELOG template) and §11 (tagging example) reference `v0.1.0`/`0.1.0`. Followed §12 literally: tagged `v0.0.1` and added a matching `[0.0.1]` CHANGELOG entry. | Resolved (using v0.0.1 per §12) |
| 2 | What software license should the project ship under? | README has a License section marked TBD. Crawl4AI itself is Apache-2.0; a compatible choice (MIT/Apache-2.0) is likely but needs an owner decision. | Open |
| 3 | Xcode project was hand-authored (no macOS/Xcode in the build environment). | The CI/dev container is Linux with no Swift toolchain. The `.xcodeproj` and Swift sources were written by hand to be valid and openable in Xcode 15+. They should be opened/verified on a real Mac before relying on the build. | Open (needs verification on macOS) |
