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
| Open GitHub issues/PRs | PR #6 (this baseline doc), as of 2026-10-16 |
| Latest checked `main` (`23b0d2f`, PRs #1–#5 merged 2026-10-16 PHT) | Core Tests ✅ (run 38806288519); iOS CI ✅ (full Gate, push run 38806288520). This is the qualified baseline |

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

## Update 2026-10-16 — final agent audit
Everything in item 5 is closed. CI warnings were fixed in PR #4, and `aws/tap` plus the `fatalError` were handled by decision in PR #6. The adapter dirs are kept by decision (DECISIONS, P4). `.agent/STATE.yaml` `repo_baseline` and `resume_token` now point at the qualified `23b0d2f`. The remaining work is owner-only: M1, M2, M4, M5.

## Update 2026-10-16 — compliance migration started (ADR-0007, P-C)
- ADR-0007 accepted: official YouTube IFrame Player in WKWebView replaces YouTubeKit +
  AVPlayer; offline downloads are removed (compiled out behind `FOCUSTUBE_LEGACY_DOWNLOADS`,
  off, during the transition; then deleted).
- Phase 1b (PR #9): core `PlayerEngine` protocol, `IFramePlayerCommand`,
  `IFrameBridgeMessage`, `IFramePlayerController`, `IFrameEmbedPage`, `YouTubeVideoID`
  with 11 unit tests. Linux `swift test`: 156/156 pass.
- Not started: phase 2 (iOS WebKit engine and switch-over), phase 3 (deletions), phase 4
  (device). The app still plays via YouTubeKit on `main` until phase 2 merges.

## Update 2026-10-16 — phase 2: downloads compiled out (ADR-0007)
Branch `feat/compile-out-downloads`: the Downloads tab, the video-page Download button,
the quality picker section and quality resolution (which called the extractor) are wrapped in
`#if FOCUSTUBE_LEGACY_DOWNLOADS` (not defined anywhere, so off). UI journeys G (download
flow/failure) and L (offline playback) are compiled out with them, and the shell/video-page
journeys now assert the Downloads tab and Download button are **absent**. The download stack
itself still compiles (deleted in phase 3). Verified only by macOS iOS CI.
## Update 2026-10-16 — phase 3 started (ADR-0007)
Removed the opt-in `LiveExtractionSmoke` and `AdaptiveLiveSmoke` tests. They only exercised
YouTubeKit stream extraction against live YouTube, which ADR-0007 forbids. `DownloadLiveSmoke`
and `PlaybackStartSmoke` follow once the playback switch-over PR lands, because it edits them.
## Update 2026-10-16 — phase 2: playback switched to the IFrame engine (ADR-0007)
Branch `feat/iframe-playback-switch` (stacked on PR #11):
- `PlayerCoordinator` is rewritten over `PlayerEngine` (no extraction, no AVPlayer). Production
  injects `WKWebViewPlayerEngine`; UI-test fixtures inject `FixturePlayerEngine`, which drives the real
  core controller with scripted ready → buffering → playing.
- `PlayerView` hosts the IFrame web view. The failure overlay names the IFrame error (e.g. embedding
  disabled) and offers "Open in YouTube"; Retry only appears for retryable errors.
- The old AVPlayer coordinator and view are renamed `LegacyAVPlayerCoordinator`/`LegacyAVPlayerView`,
  used only by the compiled-out Downloads local player and the opt-in extraction smokes. They are deleted in phase 3.
- New `PlayerCoordinatorTests` (7) use a fake engine. The video-page UI journey now asserts `player-playing`
  through the fake engine.

## Update 2026-10-16 — phase 3: app download stack and YouTubeKit removed (ADR-0007)
Branch `chore/remove-app-download-stack`:
- Deleted from the app: `DownloadManager`, `DownloadService`, `DownloadsView`, `BackgroundDownloadTransport`,
  `MediaAssetValidator`, `AdaptiveMuxer`, `StorageProviding`, `DownloadQualityPickerView`,
  `YouTubeKitMediaExtractor`, and the Legacy AVPlayer coordinator and view.
- Removed the download wiring from `AppDependencies`, `RootView`, `SearchView` and `VideoPageView`.
  The app delegate now acknowledges leftover background sessions immediately.
- Removed the UI-test fixtures for extraction and download, the download scenarios, and the
  `FOCUSTUBE_LEGACY_DOWNLOADS` flag. The compiled-out journeys are gone.
- Deleted the download, extraction and AVPlayer unit tests and every live extraction smoke.
- **YouTubeKit is removed from `project.yml`.**
- Kept on purpose for a separate data-cleanup PR: the `DownloadedMedia`/`DownloadRecord` SwiftData
  models, which stay in the schema to avoid a migration risk; the `LibraryStore` downloaded index; and the
  Settings "Downloads" storage section, which reports leftover files.
- The core package still contains the extraction and download types. They are now unused by the app and
  will be deleted in the next PR.

## Update 2026-10-16 — phase 3: core extraction and download planning removed (ADR-0007)
Branch `chore/remove-core-extraction` (stacked on the app-removal PR) deletes these core types and their tests:
`MediaExtracting`, `ResolvedMedia`/`MediaStream`, `MediaStreamFilter`, `AdaptiveSelection`, `ExtractionError`,
`DownloadQuality`, `DownloadQualityPicker`, `DownloadPlanner`, `DownloadCoordinator`, `DownloadReconciler`,
`DownloadRetryPolicy` and `StorageEstimator`. Kept for now, because the persisted `DownloadRecord`/library
index still needs them: `DownloadTask`/`DownloadState`/`DownloadQueue`/`DownloadTransport` (`FileManaging`) and
`OfflineLibraryPolicy`. Linux `swift test`: 109/109 pass.

## Update 2026-10-16 — ADR-0008 core (no Google Cloud)
- PR #18: the `YouTubeLink` parser.
- PR #19: the Atom feed parser and client, the oEmbed client and `HTTPFetching`.
- Branch `feat/core-local-library-aggregator`: `LocalLibrary` (subscriptions, saved playlists, Watch Later,
  history and resume, local search), `LocalLibraryStore` (atomic JSON; a corrupt file is moved aside) and
  `PublicFeedAggregator` (4 concurrent fetches, 15-minute per-feed interval, failures keep the stale cache,
  Shorts firewall by `/shorts/` link, portrait oEmbed or a learned duration ≤180 s, de-dup, newest first).
  Linux `swift test`: 177/177 on that branch.
- Next: app wiring (remove GoogleSignIn and `YouTubeDataClient`; add the Add tab, the local feed and the oEmbed video page).
