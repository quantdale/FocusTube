# BLOCKERS — Phase 1 Assessment

## Needs Michael (morning queue)
| # | What | Exact fix | Unblocks |
|---|------|-----------|----------|
| M1 | iPhone test batch, Batch A A1–A14 | Run [`docs/MAC_FINALIZATION_CHECKLIST.md`](MAC_FINALIZATION_CHECKLIST.md) on a Mac with the iPhone connected | V1 criteria 1–3 and PERSONAL_RELEASE |
| M2 | Mac, Xcode, and signing | Install Xcode on a Mac, open the project, set your Apple ID team under Signing & Capabilities, and build to the device | M1, plus any on-device debugging |
| M4 | Google OAuth client and `Secrets.local.xcconfig` | Create an iOS OAuth client in the [Google Cloud Console](https://console.cloud.google.com/apis/credentials) and enable the YouTube Data API v3. Copy `Config/Secrets.local.xcconfig.example` to `Config/Secrets.local.xcconfig` and fill in the client ID and reversed client ID | Real sign-in, M1 auth items, M5 |
| M6 | Confirm acceptance of ADR-0007 losses: no offline downloads, no background audio, PiP/lock-screen not guaranteed | Reply on the docs PR, or object | Phase 3 deletions (agent proceeds with phases 1–2 meanwhile; Michael was told and has not objected) |
| M5 | Authenticated live-smoke run | On the [Actions tab](https://github.com/quantdale/FocusTube/actions/workflows/ios-ci.yml), click "Run workflow" with `live_smoke=true`. The Google token secrets must be set first | V1 criterion 4 and the YouTubeKit 0.4.8 viability check |
| M3 | (Resolved 2026-10-16) CI jobs blocked by a billing/spending limit | Repo made public; CI runs again | — |


| ID | Blocker | Severity | Owner | Unblock |
|----|---------|----------|-------|---------|
| B1 | ✅ **Resolved 2026-10-16 (PR #1, `8448140`)**: `main` iOS CI was red because of a flaky ordering assertion in `YouTubeDataClientTests.testSubscriptionFeedChunksVideosListBeyondIDCap` (introduced with `3fbf1d8`) | High (gate integrity) | agent | Make the assertion order-independent, or make the scripted performer record by batch index. Then re-run CI. |
| B2 | ✅ **Resolved 2026-10-16**: re-qualified at `8448140` (Core and iOS CI green on PR #1). Previously, the qualified baseline `7a70943` is behind the code on `main` | Medium | agent + CI | Re-qualify after B1, and repoint the Batch A docs at the new SHA |
| B3 | Device validation needs a Mac, Xcode, signing, and an iPhone | External | owner | MAC_FINALIZATION_CHECKLIST.md |
| B4 | Real Google OAuth client and Data API v3 project | External | owner | Create an iOS OAuth client and fill in `Config/Secrets.local.xcconfig` |
| B5 | The live smoke needs owner dispatch (`live_smoke=true`) | External | owner | Use workflow_dispatch on `ios-ci.yml` |
| B6 | No iOS toolchain on this Linux box | Environment | — | Use macOS CI or a Mac |
| B7 | Resolved in PR #8: the `ScriptedPerformer` in `YouTubeDataClientTests` mutated state without a lock under concurrent feed hydration. `xctest` died with SIGTRAP on macOS CI (PR #7 run 38817976196) | High (gate integrity) | agent | Guard the performer with an `NSLock`, the same pattern the other test performers use |
| B8 | WebKit/IFrame behavior cannot be exercised on Linux | Environment | agent + CI/owner | Phase 2 relies on macOS iOS CI for build/UI tests and on a device for real playback |
| B9 | Live smoke as defined tests YouTubeKit extraction, which ADR-0007 removes | Low | agent | The extraction smokes are deleted in phase 3. Re-scope M5 to an authenticated Data API smoke (not yet written) |
