# Checkpoint — INTEGRATION_COMPLETION_V1 PHASE A compile repairs (partial)

- Campaign: INTEGRATION_COMPLETION_V1
- Milestone/Gate: M1_MEDIA_VIABILITY / G0 revalidation (still red)
- Packet: INTEGRATION-A (PHASE A restore buildability)
- State: partial
- Commit: 63d637d (d21c272 = compile fixes, 63d637d = CI diagnostics)

## What changed
- Static audit swarm over all 73 Swift files found and fixed real Swift 6
  compile errors that explain why Core Tests NEVER passed on CI (every run in
  history failed; recent "success" rows were `|| true` masking):
  - DownloadState: added Hashable (required by Hashable DownloadTask) and the
    `.finalizationFailed` case already referenced by DownloadCoordinator.
  - Tests/FocusTubeCoreTests: stub structs that mutate in non-mutating protocol
    witnesses became final classes (@unchecked Sendable); 9 non-exhaustive
    typed-catch sites got catch-all XCTFail arms.
  - App layer: BackgroundDownloadTransport optional-tuple guard + import os;
    DownloadManager.makeMux no longer wraps async work in sync MainActor.run;
    PlayerCommandTarget is @MainActor and PlayerCoordinator.seek(to:)
    implemented; NowPlayingInfoBuilder uses MPMediaItemArtwork(image:);
    SearchStore.nextPageToken exposed for pagination.
- FocusTubeTests/DownloadCoordinatorTests: completion-path tests now drive
  coordinator.begin("d1") first so events flow through valid transitions
  (.queued -> .downloading -> .validating); previously finalize silently
  returned on invalid transition and tests would fail at runtime.
- core.yml publishes swift test errors to the public step summary on failure
  (Actions log API needs auth; summary was NOT retrievable anonymously either
  — kept as best-effort channel).

## Acceptance evidence
- Observed via GitHub API (unauthenticated): run 32430555251 Core Tests
  conclusion=failure at 63d637d; run 32430555223 iOS CI conclusion=failure.
  Exact compiler output still unread (logs need admin auth; annotations only
  carry "exit code 1"; step summary not exposed anonymously).
- No local compiler verdict yet: Windows Swift 6.3.3 toolchain is being
  extracted from the official bundle (WiX burn -> dark.exe -> lessmsi) under
  .swift-toolchain/ (gitignored).

## Known failures or deferred items
- Core Tests red on CI (unknown remaining error(s) after this push).
- iOS CI red (app-target compile status unknown; YouTubeKit API surface
  unverifiable off-macOS).
- Phase C gaps logged during code review (fix after buildability):
  DownloadService swallows extraction/enqueue/completion errors silently;
  component temp files are never cleaned after successful finalize;
  reconcileOnLaunch cancels previous background tasks instead of reattaching
  them via session getAllTasks; storage-size estimate never passed to enqueue.

## Durable decisions made
- none (no ADR-level deviations)

## Exact next waypoint
- Finish local toolchain extraction (.swift-toolchain/flat/{rtl,cli.asserts}),
  put binutils on PATH, run `swift build`+`swift test` for FocusTubeCore,
  fix every reported error until green, then push and observe Core Tests run.

## Resume commands
```bash
cd "/c/Users/Michael Roy/Documents/FocusTube/.swift-toolchain/flat"
../lessmsi/lessmsi.exe x rtl.msi && ../lessmsi/lessmsi.exe x cli.asserts.msi
# then locate swift.exe under rtl/cli.asserts SourceDir trees, set PATH, run:
cd "/c/Users/Michael Roy/Documents/FocusTube" && swift test
```
