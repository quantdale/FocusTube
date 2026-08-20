# 15 — Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| YouTube changes break YouTubeKit local extraction | High over project lifetime | High | adapter boundary, pinned version, live smoke test, deliberate dependency updates |
| YouTubeKit release lags breaking upstream change | Medium | High | fail clearly; do not hide with unapproved fallback; keep app/account features independent |
| Adaptive 1080p native mux incompatibility | Medium | High | prove in M1 before broad UI; prefer compatible MP4/M4A; ADR if native path insufficient |
| Signed stream URL expires mid-download | Medium | High | typed needsReResolve state and restart/re-resolution policy |
| GitHub runner image loses expected simulator/Xcode exact version | Medium | Medium | discover runtimes; prefer Xcode 26.6 but accept approved 26.x; log toolchain |
| Windows agent cannot run Apple frameworks locally | Certain | Medium | FocusTubeCore split + remote macOS CI |
| Search quota exhausted | Medium | Medium | explicit-submit search, local query history, quota-aware paging |
| Google OAuth cannot be automated safely | Certain | Low/Medium | fake auth for CI; occasional real integration test only |
| Filesystem/SwiftData drift | Medium | High | reconciliation, atomic final moves, migrations, orphan quarantine |
| App accidentally introduces Shorts mechanics | Medium | Critical to product | central ShortFormPolicy + UI architecture + regression tests |
| Personal-project extraction/download conflicts with platform terms | Material | High if distributed | keep personal scope, document policy, no commercialization without review |
| CI macOS cost becomes excessive | Low/Medium | Medium | fast core tests locally, minimize simulator jobs, consider persistent remote Mac only if justified |
