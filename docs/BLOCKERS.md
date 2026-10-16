# BLOCKERS — Phase 1 Assessment

## Needs Michael (morning queue)
| # | What | Exact fix | Unblocks |
|---|------|-----------|----------|
| M1 | iPhone test batch, Batch A A1–A14 | Run [`docs/MAC_FINALIZATION_CHECKLIST.md`](MAC_FINALIZATION_CHECKLIST.md) on a Mac with the iPhone connected | V1 criteria 1–3 and PERSONAL_RELEASE |
| M2 | Mac, Xcode, and signing | Install Xcode on a Mac, open the project, set your Apple ID team under Signing & Capabilities, and build to the device | M1, plus any on-device debugging |
| M6 | Confirm acceptance of ADR-0007 losses: no offline downloads, no background audio, PiP/lock-screen not guaranteed | Reply on the docs PR, or object | Phase 3 deletions (agent proceeds with phases 1–2 meanwhile; Michael was told and has not objected) |
| M3 | (Resolved 2026-10-16) CI jobs blocked by a billing/spending limit | Repo made public; CI runs again | — |


| ID | Blocker | Severity | Owner | Unblock |
|----|---------|----------|-------|---------|
| B1 | ✅ **Resolved 2026-10-16 (PR #1, `8448140`)**: `main` iOS CI was red because of a flaky ordering assertion in `YouTubeDataClientTests.testSubscriptionFeedChunksVideosListBeyondIDCap` (introduced with `3fbf1d8`) | High (gate integrity) | agent | Make the assertion order-independent, or make the scripted performer record by batch index. Then re-run CI. |
| B2 | ✅ **Resolved 2026-10-16**: re-qualified at `8448140` (Core and iOS CI green on PR #1). Previously, the qualified baseline `7a70943` is behind the code on `main` | Medium | agent + CI | Re-qualify after B1, and repoint the Batch A docs at the new SHA |
| B3 | Device validation needs a Mac, Xcode, signing, and an iPhone | External | owner | MAC_FINALIZATION_CHECKLIST.md |
| B6 | No iOS toolchain on this Linux box | Environment | — | Use macOS CI or a Mac |
| B7 | Resolved in PR #8: the `ScriptedPerformer` in `YouTubeDataClientTests` mutated state without a lock under concurrent feed hydration. `xctest` died with SIGTRAP on macOS CI (PR #7 run 38817976196) | High (gate integrity) | agent | Guard the performer with an `NSLock`, the same pattern the other test performers use |
| B8 | WebKit/IFrame behavior cannot be exercised on Linux | Environment | agent + CI/owner | Phase 2 relies on macOS iOS CI for build/UI tests and on a device for real playback |

_2026-10-16: M4, M5, B4, B5 and B9 were removed by ADR-0008 (no Google Cloud, no Data API, no OAuth)._
