# BLOCKERS — Phase 1 Assessment

| ID | Blocker | Severity | Owner | Unblock |
|----|---------|----------|-------|---------|
| B1 | ✅ **Resolved 2026-10-16 (PR #1, `8448140`)**: `main` iOS CI was red because of a flaky ordering assertion in `YouTubeDataClientTests.testSubscriptionFeedChunksVideosListBeyondIDCap` (introduced with `3fbf1d8`) | High (gate integrity) | agent | Make the assertion order-independent, or make the scripted performer record by batch index. Then re-run CI. |
| B2 | ✅ **Resolved 2026-10-16**: re-qualified at `8448140` (Core and iOS CI green on PR #1). Previously, the qualified baseline `7a70943` is behind the code on `main` | Medium | agent + CI | Re-qualify after B1, and repoint the Batch A docs at the new SHA |
| B3 | Device validation needs a Mac, Xcode, signing, and an iPhone | External | owner | MAC_FINALIZATION_CHECKLIST.md |
| B4 | Real Google OAuth client and Data API v3 project | External | owner | Create an iOS OAuth client and fill in `Config/Secrets.local.xcconfig` |
| B5 | The live smoke needs owner dispatch (`live_smoke=true`) | External | owner | Use workflow_dispatch on `ios-ci.yml` |
| B6 | No iOS toolchain on this Linux box | Environment | — | Use macOS CI or a Mac |
