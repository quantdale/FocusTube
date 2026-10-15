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
Real OAuth, Data API mutations, live YouTubeKit extraction, background
URLSession under suspension, PiP, lock screen, headset, and storage
reclamation.

## Flake fix verification (2026-10-15, branch `fix/flaky-subscription-feed-order`)
| Step | Command | Result |
|------|---------|--------|
| Test core | `swift test` | ✅ 141 XCTest + 11 swift-testing, 0 failures |
| Flake probe | `swift test --skip-build --filter testSubscriptionFeedChunksVideosListBeyondIDCap` ×40 | ✅ 0/40 failed (was 10/40) |

## PR #1 merged (2026-10-16 03:2x PHT)
`main` tip `8448140`: PR #1 checks were Core ✅ ×2 and iOS CI ✅ (26m59s, full Gate, UI tests).
The Node 20 deprecation was the only remaining CI warning; it is being fixed on `ci/node24-actions`.

## Re-qualified at `09a7ee3` (2026-10-16 ~05:00 PHT)
`main` tip `09a7ee3` (PR #3 squash, on top of `7e650e0` PR #4) was checked as follows:
- Core Tests ✅ on PR #3 (runs 38801410890 and 38801416935).
- iOS CI ✅ on PR #3 (run 38801417134, 32m40s, full Gate including UI tests).
- PR #4 (`7e650e0`): Core ✅ and iOS CI ✅ (run 38797704060).

This is the **current qualified baseline**. Device Batch A (A1–A14) should target `09a7ee3` or newer.
