# PROGRESS — Phase 1 Assessment (2026-10-15)

## What FocusTube is
FocusTube is a personal-use native iOS (SwiftUI, iOS 17+, Swift 6) YouTube
client built for deliberate long-form viewing. It has four tabs: Home
(subscription feed), Search (explicit submit), Downloads, and Library. Shorts
are hard-blocked. Media comes from local YouTubeKit extraction and plays in
AVPlayer. Downloads use a background URLSession, and adaptive 1080p uses an
AVFoundation mux. Account features use GoogleSignIn plus a typed YouTube Data
API v3 client. Data lives in SwiftData plus the filesystem. There is no
backend.

## Architecture
- `Sources/FocusTubeCore` (30 files): a platform-neutral domain covering
  quality ladder, Shorts policy, download state machine, planner, queue,
  reconciler, feed aggregation, and the YouTube Data client. It has no Apple
  UI or media imports and builds on Linux.
- `App/` (32 files): SwiftUI features, the composition root
  (`AppDependencies`), DownloadManager, AdaptiveMuxer, the YouTubeKit adapter
  behind `MediaExtracting`, auth, and background media.
- Tests: 25 core test files (141 XCTest + 11 swift-testing), 21 app-hosted
  XCTest files (including opt-in live smokes), and the XCUITest `Journeys`
  suite (A–L, 20 journeys).
- Build: XcodeGen `project.yml` (no `.xcodeproj` committed). CI uses
  GitHub Actions on `macos-26`: `core.yml` and `ios-ci.yml` with a
  fail-closed Gate.
- Control plane: `.agent/` (STATE, WAYPOINTS, checkpoints, work packets) and
  six ADRs.

## Completion status
| Area | Status |
|------|--------|
| M0–M8 implementation (extraction, playback, downloads incl. adaptive 1080, auth/API, Home, Search, video page/comments, Library, background media) | Done per checkpoints |
| Hardening V1–V3 and backlog HB-001..030 | Resolved |
| OPT_PERFORMANCE_V1 | Done; its flaky test was fixed in PR #1 |
| Device validation (Batch A) | **Not done**; owner-only |
| Live authenticated smoke | **Not done**; owner-only |
| Open GitHub issues/PRs | PR #5 (DownloadRetryPolicy tests), as of 2026-10-16 |
| Latest checked `main` (`09a7ee3`, PRs #1–#4 merged 2026-10-16 PHT) | Core Tests ✅; iOS CI ✅ (full Gate on PR #3, run 38801417134). This is the qualified baseline |

## Top 5 issues
1. **Flaky core test on `main`** (`YouTubeDataClientTests.testSubscriptionFeedChunksVideosListBeyondIDCap`).
   Parallel hydration in `3fbf1d8` made request order nondeterministic. It
   failed iOS CI run 33293629424 and failed 10 of 40 times on Linux. The test
   is the problem, not the product: results are index-keyed.
2. **Qualification drift.** App code changed in `3fbf1d8` after the qualified
   SHA `7a70943`. The device batch is still pointed at `7a70943`.
3. **No real-device or real-account evidence yet.** OAuth, Data API writes,
   background transfer, PiP, and lock screen are verified only against fakes
   and the Simulator.
4. **External dependency risk.** YouTubeKit local extraction (pinned 0.4.8)
   is the single point of failure, and it is unverified for about 7 weeks.
5. **CI deprecation warnings.** Node 20 actions are being force-run on
   Node 24, and Homebrew warns about an untrusted `aws/tap`. Minor tech debt:
   a `fatalError` last-resort fallback in `AppDependencies`, a stale dated
   narrative in `docs/13-ROADMAP.md`, and five parallel agent-adapter
   directories.

## Update 2026-10-15 — flake fix (branch `fix/flaky-subscription-feed-order`)
Item 1 above is fixed in the test only: `testSubscriptionFeedChunksVideosListBeyondIDCap` now
orders the captured `videos.list` batches by their first id before asserting
`[50, 11]` chunking and full id coverage. Production code is unchanged. It already
places batch results by index (`fetchDetailBatchesConcurrently`).
