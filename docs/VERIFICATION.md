# VERIFICATION — Phase 1 Assessment (2026-10-15, box: Debian 13 x86_64)

## Local (Linux)
| Step | Command | Result |
|------|---------|--------|
| Toolchain | Swift 6.0.3-RELEASE (debian12 tarball, user-space; libncurses.so.6 symlinked to libncursesw) | OK |
| Build core | `swift build` | ✅ Build complete; warnings only (e.g. `@discardableResult` on a Void function in the playback state machine) |
| Test core | `swift test` | ✅ 141 XCTest + 11 swift-testing, 0 failures (single run) |
| Flake probe | `swift test --skip-build --filter testSubscriptionFeedChunksVideosListBeyondIDCap` ×40 | ❌ **10/40 failed** |
| iOS app / XCTest / XCUITest | — | Not runnable on Linux; needs macOS/Xcode |

## Hosted CI (read via `gh`, read-only)
| Run | SHA | Result |
|-----|-----|--------|
| Core Tests 33293629420 | 86516e0 | ✅ |
| iOS CI 33293629424 | 86516e0 | ❌ The "Test FocusTubeCore" step failed on the flaky test above (asserted 11 vs 50; batch order v50.. before v0..). The Build and UI steps were skipped, so the Gate failed (unit=missing, ui=missing). |
| iOS CI 32920606126 | ccbe829 | ✅ |
| iOS CI 32891558884 | 7a70943 (qualified) | ✅ per checkpoint (20/20 journeys, 141 unit tests) |

## Not verified (owner/macOS)
(Superseded by ADR-0007/0008: no OAuth, Data API or extraction.) Background
URLSession under suspension, PiP, lock screen, headset, and storage
reclamation.

## Flake fix verification (2026-10-15, branch `fix/flaky-subscription-feed-order`)
| Step | Command | Result |
|------|---------|--------|
| Test core | `swift test` | ✅ 141 XCTest + 11 swift-testing, 0 failures |
| Flake probe | `swift test --skip-build --filter testSubscriptionFeedChunksVideosListBeyondIDCap` ×40 | ✅ 0/40 failed (was 10/40) |

## PR #1 merged (2026-10-16 03:2x PHT)
`main` tip `8448140`: PR #1 checks were Core ✅ ×2 and iOS CI ✅ (26m59s, full Gate, UI tests).
The Node 20 deprecation was the only remaining CI warning; it was fixed by the actions v7 bump (PR #4, `7e650e0`).

## Re-qualified at `23b0d2f` (2026-10-16 ~05:30 PHT)
`main` tip `23b0d2f` (PR #5 squash, test-only, on top of `09a7ee3` PR #3 and `7e650e0` PR #4) was checked as follows:
- `23b0d2f` push: Core Tests ✅ (run 38806288519); iOS CI ✅ (run 38806288520, 25m51s, full Gate).
- Core Tests ✅ on PR #3 (runs 38801410890 and 38801416935).
- iOS CI ✅ on PR #3 (run 38801417134, 32m40s, full Gate including UI tests).
- PR #4 (`7e650e0`): Core ✅ and iOS CI ✅ (run 38797704060).

This is the **current qualified baseline**. Device Batch A (A1–A14) should target `23b0d2f` or newer.

## Compliance migration (ADR-0007), 2026-10-16
| Item | Evidence | Status |
|------|----------|--------|
| Core IFrame controller / bridge parsing / command JS / embed HTML | Linux `swift test` 156/156 (11 new in `IFramePlayerTests`) on branch `feat/iframe-player-core` | ✅ Linux; Core CI on PR #9 pending at time of writing |
| Embed page actually loads the IFrame API in WKWebView | — | ❌ **Unverified** (no WebKit on Linux) |
| JS→Swift bridge round-trip (`messageHandlers.focustube`) | — | ❌ **Unverified** until macOS CI/device runs it |
| Inline playback, autoplay without gesture, fullscreen/rotation | — | ❌ **Unverified** (device only) |
| PiP / lock screen / background behavior under IFrame | — | ❌ **Unverified**; expected unsupported (ADR-0007) |
| iOS target compiles without YouTubeKit | — | ❌ Not attempted yet (phase 3) |
Rule: nothing WebKit-related is marked verified until macOS CI builds/tests it or a device runs it.
| `PlayerCoordinator` over `PlayerEngine` (load deferral, resume, invalid id, typed errors, progress throttle, stop) | 7 `PlayerCoordinatorTests` pass on Linux in a scratch package: same sources, with `@Observable` stripped because the Linux toolchain's Observation library fails to link | ✅ logic on Linux; the real file with `@Observable` is unverified until macOS CI |
| App target compiles with the IFrame switch-over, and UI journeys pass with `FixturePlayerEngine` | — | ❌ Pending macOS iOS CI (PR for `feat/iframe-playback-switch`) |
| Real IFrame playback on device | — | ❌ Unverified |
| App builds and tests pass without YouTubeKit or the download stack | — | ❌ Pending macOS iOS CI (`chore/remove-app-download-stack`) |
| Core with extraction/download planning removed | Linux `swift build` + `swift test` 109/109 (`chore/remove-core-extraction`) | ✅ Linux; app side pending macOS CI |

## ADR-0008 (no Google Cloud), 2026-10-16
| Item | Status |
|------|--------|
| Link parser, Atom parser, oEmbed decoding, local library policies, feed aggregator | Linux unit tests (see each PR) |
| Live fetch of `feeds/videos.xml` and `oembed` from the app | ❌ Unverified until device. CI uses fixtures only |
| Add tab, local feed and video page in the app | ❌ Pending macOS CI, then device |

| App builds and UI journeys pass with GoogleSignIn and the Data API removed (PR #22) | iOS CI run 38899779583 on d75a878: unit 45/45 passed and UI exit 0, but the Gate went red on a stray xcodebuild exit 65 after success (infra). Rerun pending | ⏳ Pending a green rerun |
