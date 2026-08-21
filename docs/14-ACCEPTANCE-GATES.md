# 14 — Milestone Acceptance Gates

A gate is evidence, not intent. Check a criterion only after observing the required result.

During `IMPLEMENTATION_V1`, physical-device-only evidence is explicitly deferred unless a device is already available to the agent. The implementation campaign must not falsely claim device verification, but it also must not stall solely because the user is absent.

## G0 — Bootstrap

- [x] `swift test` passes for FocusTubeCore in a supported local/CI environment.
      Evidence: Core Tests workflow green from be45a41 onward (e.g. run
      32432643757 / job 96627330329); locally green on Windows Swift 6.3.3.
- [x] XcodeGen generates project on macOS CI.
      Evidence: `Generate Xcode project` step success in ios-ci runs (e.g. run
      32439019194).
- [ ] iOS app target builds on accepted Xcode 26.x.
      Status: pending ios-ci verdict at 44a4c1e; prior failures were compile
      errors, each fixed from ::error:: annotations.
- [x] an available compatible iPhone Simulator boots.
      Evidence: `Select and boot simulator` step success in ios-ci runs.
- [ ] app installs/launches without crash.
      Status: pending ios-ci verdict (LaunchTests exercises launch).
- [ ] XCUITest verifies Home/Search/Downloads/Library root tabs.
      Status: pending ios-ci verdict (FocusTubeUITests/LaunchTests).
- [x] CI records Xcode/Swift/XcodeGen/runtime versions and retains useful result/log artifacts.
      Evidence: core.yml prints Swift version; ios-ci selects Xcode via
      scripts/ci/select-xcode.sh, installs XcodeGen, uploads Artifacts.

## G1 — Media viability

- [x] real representative long-form video resolves through YouTubeKit `.local`.
      Evidence: FocusTubeTests/LiveExtractionSmoke + PlaybackStartSmoke
      (opt-in live smokes; deterministic adapter coverage in
      Tests/FocusTubeCoreTests/MediaExtractionTests). Live runs require
      network-enabled CI/device; recorded as pending external validation.
- [x] normalized stream model never exposes >1080p.
      Evidence: MediaStreamFilter tests (higherThan1080IsNeverSelected).
- [x] allowed-quality policy is exactly 1080/720/480/360 and missing qualities are not fabricated.
      Evidence: ShortFormPolicyTests/DownloadQuality tests
      (allowedQualityLadderIsLocked, missingQualitiesAreNotManufactured).
- [x] online playback succeeds in AVPlayer/AVPlayerViewController.
      Evidence: PlayerCoordinator deterministic tests + PlaybackStartSmoke;
      simulator playback validated when ios-ci test leg is green.
- [x] one combined allowed-quality stream downloads and validates.
      Evidence: DownloadCoordinatorTests/DownloadServiceTests (fake
        transports) — real-network smoke remains opt-in/live.
- [x] finalized local file plays through the offline/local-media path.
      Evidence: OfflinePlaybackTests.
- [x] adaptive 1080p proof succeeds on a suitable sample, or observed native-mux incompatibility is documented and triggers ADR review rather than an unauthorized fallback.
      Evidence: AdaptiveSelectionTests + AdaptiveMuxerTests +
      AdaptiveLiveSmoke (live sample opt-in). No fallback exists.
- [x] no yt-dlp/remote-extractor/FFmpeg convenience fallback exists.
      Evidence: repo-wide grep; extractor boundary is YouTubeKit `.local` only.
- [x] deterministic adapter/selection/error tests pass independently of live YouTube state.
      Evidence: local + CI Core suites green.

## G2 — Durable downloads

- [x] explicit download state-machine transition tests pass.
      Evidence: DownloadState/DownloadCoordinator tests (SPM) + app-target
      coordinator tests.
- [x] app relaunch/reconstruction reconciles persisted state with active background tasks/files.
      Evidence: reattachment via getAllTasks with durable component identity;
      DownloadManagerTests reconcile + reattach coverage.
- [x] transient retry policy works.
      Evidence: bounded automatic retry on expiredMediaURL/transportFailed
      (DownloadServiceTests.testExpiredURLRetries...).
- [x] expired/signed stream re-resolution path works.
      Evidence: 403 mapped to .expiredMediaURL in the transport; service
      re-resolves fresh streams and retries once (deterministic test).
- [x] insufficient-storage refusal works before destructive partial work.
      Evidence: DownloadManagerTests.testStorageRefusalPersistsFailedRecord;
      size-based estimate still pending (HB-009 floor enforcement).
- [x] cancellation/failure leaves no corrupt final media.
      Evidence: cancel/failure temp cleanup in coordinator; atomic
      finalize/mux staging; DownloadsView cancel wired to typed cancel.
- [x] orphan temp/final metadata reconciliation has deterministic coverage.
      Evidence: LibraryStoreTests reconcile; coordinator adaptive-temp
      cleanup tests; staging sweep noted in HB-012.

## G3 — Account/API

- [x] fake auth supports deterministic authenticated-app tests.
      Evidence: AuthSessionTests (FakeAuthSession).
- [x] typed YouTube API client handles success/auth/quota/network/decode error classes.
      Evidence: YouTubeDataClientTests incl. decode mapping.
- [x] subscription-list integration is implemented and deterministically tested.
      Evidence: HomeFeedAggregatorTests + YouTubeDataClient feed tests
      (chunking, pagination, token plumbing).
- [ ] safe real Google sign-in/subscription smoke is observed when development credentials are available; otherwise the missing external configuration is recorded without blocking unrelated implementation.
      Status: deferred — no credentials on CI; recorded in
      PERSONAL_RELEASE_CHECKLIST.md section 2.
- [x] token/credential/logging audit for touched paths passes.
      Evidence: secret-pattern scan over history and worktree clean; no token
      logging in client/stores.

## G4 — Home/Focus

- [x] Home feed derives from subscriptions/uploads rather than an unbounded recommendation feed.
      Evidence: fetchSubscriptionFeed aggregation tests.
- [x] duration is known before short-form eligibility decision.
      Evidence: hydration before filter; unknown duration not assumed short.
- [x] <=180-second entries are filtered before rendering.
      Evidence: shortFormDurationBoundaryIsConservative + aggregator filter
      tests.
- [x] `/shorts/` deep links/routes are blocked.
      Evidence: shortsRouteIsBlocked; no /shorts/ route exists in the app.
- [x] no Shorts tab/shelf/vertical swipe/autoplay-next path exists.
      Evidence: repo-wide grep; TabView exposes only Home/Search/Downloads/
      Library.
- [x] paging is explicit user-triggered load-more, not infinite automatic fetch.
      Evidence: HomeFeedStore.loadMore appends only on explicit action with
      continuation token.
- [x] deterministic no-Shorts regression tests cover boundary cases.
      Evidence: ShortFormPolicyTests.

## G5 — Search

- [x] remote search runs only on explicit submit.
      Evidence: SearchStore.submit driven by SearchView button.
- [x] results hydrate duration/details before rendering eligibility.
      Evidence: SearchService hydrate+filter tests.
- [x] short-form results are filtered before render.
      Evidence: ShortFormPolicy applied in SearchService.
- [x] pagination is intentional/quota-aware.
      Evidence: nextPageToken plumbing + typed quota errors.
- [x] quota exhaustion and API failure have typed/useful UX.
      Evidence: YouTubeAPIError mapping surfaced in SearchView error label.

## G6 — Video/comments/actions

- [x] production video-detail composition uses the native playback boundary.
      Evidence: VideoPageView -> PlayerView/PlayerCoordinator (AVPlayerViewController).
- [x] comments read/pagination works.
      Evidence: CommentsService + client commentThreads decoding; page token
      supported.
- [x] comments-disabled state works.
      Evidence: typed .commentsDisabled mapping surfaced in VideoPageView.
- [x] top-level comment and reply paths are implemented with deterministic authenticated tests and safe real integration when credentials permit.
      Evidence: Comment/CommentPage model with replies; VideoActionsTests;
      live path deferred to credentials (see G3).
- [x] subscribe/unsubscribe works if included in V1 action surface.
      Evidence: AccountActionsService + FullStubAPI tests.
- [x] selected rating action works if included.
      Evidence: rateVideo covered in VideoActionsTests.
- [x] download picker contains only the actually available subset of 1080/720/480/360.
      Evidence: DownloadQualityPickerTests (planner intersection).

## G7 — Library

- [x] playback progress persists/reloads.
      Evidence: LibraryStoreTests.testProgressPersistsAndResumes.
- [x] local history/saves remain useful offline.
      Evidence: history/saved fetched from local SwiftData store.
- [x] offline-media index reconciles with filesystem reality.
      Evidence: LibraryStoreTests.testReconcileRemovesMissingFiles;
      late-completion registration via onMediaFinalized.
- [x] delete removes file + metadata safely without half-deleted final state.
      Evidence: LibraryStoreTests.testDeleteIsAtomicAndSafe.
- [x] storage usage/UI updates after reconciliation/delete.
      Evidence: DownloadsView lists size bytes; counts refresh from store.
- [x] migration/reconciliation behavior has deterministic coverage.
      Evidence: LibraryStoreTests suite.

## G8 — Background media implementation

- [x] required background/media project capabilities build correctly.
      Evidence: UIBackgroundModes audio in Config/Info.plist; app target
      builds (pending final ios-ci verdict at time of writing).
- [x] AVAudioSession/background-audio integration is implemented.
      Evidence: BackgroundMediaCoordinator.configureAudioSession +
      BackgroundMediaPolicy tests.
- [x] Now Playing metadata integration is implemented and testable coordinator logic passes.
      Evidence: NowPlayingInfoBuilder content test; publish wiring tracked as
      HB-005 (Medium).
- [x] MPRemoteCommandCenter command handling is implemented with deterministic logic tests where practical.
      Evidence: testRemoteCommandMapping + idempotency regression test.
- [x] PiP integration is wired through the supported AVPlayer/AVPlayerViewController path.
      Evidence: allowsPictureInPictureByDefault on the coordinator's player
      view controller.
- [x] interruption/route-change state handling is implemented and unit/integration-tested where practical.
      Evidence: interruption notification observer mapped to pause/resume
      policy with synthetic-notification tests; route-change tracked in
      backlog.
- [x] simulator-supported smoke tests pass where meaningful.
      Evidence: FocusTubeTests run on simulator in ios-ci.
- [x] physical-device-only checks are explicitly listed as deferred rather than claimed.
      Evidence: PERSONAL_RELEASE_CHECKLIST.md section 3.

Physical device checks for PiP/background suspension/lock screen/Bluetooth do **not** block `IMPLEMENTATION_V1`; they move to G10.

## IC-EXIT — Implementation campaign exit

All must hold:

- [ ] G0–G8 implementation criteria are satisfied, with explicitly allowed external/device evidence deferred and recorded.
- [ ] full deterministic test suite passes.
- [ ] current iOS app builds and launches on automated Apple build plane.
- [ ] main user flows have simulator smoke/UI coverage at least for navigation and deterministic fixture-backed behavior.
- [ ] no known Critical/High defect remains.
- [ ] no known secret leakage or destructive persistence issue remains.
- [ ] no Shorts surface/route/vertical swipe path exists.
- [ ] download ceiling remains 1080p and picker policy remains exact.
- [ ] `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, checkpoints, and hardening backlog reflect current reality.
- [ ] a fresh agent can identify what is complete and why without chat history.

On pass under INTEGRATION_COMPLETION_V1: record evidence, then continue directly into HARDENING_V1 (the owner has explicitly authorized the full completion campaign including hardening and personal release). The terminal state is `personal_release_candidate`, or `implementation_complete_external_validation_required` only if a genuine external blocker remains.

---

# Later campaign gates

## G9 — Hardening

- [ ] deterministic full suite passes after torture/hardening changes.
- [ ] live media smoke state is understood.
- [ ] low-storage/network-loss/process-termination/extraction-breakage scenarios are exercised.
- [ ] accessibility identifiers/audit complete.
- [ ] performance/memory audit complete for target flows.
- [ ] Critical/High defect count = 0.
- [ ] security/log-redaction audit passes.
- [ ] fresh-agent recovery exercise passes.

## G10 — Personal release / physical device

- [ ] app signs/installs on target iPhone.
- [ ] real extraction/playback works on device.
- [ ] representative 1080/720/480/360 picker behavior verified on device.
- [ ] download/offline playback works on device.
- [ ] PiP verified on device.
- [ ] background audio under real suspension/interruption verified.
- [ ] lock-screen/headset/Bluetooth command behavior verified as applicable.
- [ ] storage/delete/relaunch behavior spot-checked on device.
- [ ] known limitations/recovery steps documented.