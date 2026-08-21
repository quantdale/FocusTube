# Checkpoint — INTEGRATION_COMPLETION_V1 PHASE A complete, PHASE B/C landed

- Campaign: INTEGRATION_COMPLETION_V1
- Milestone/Gate: M1_MEDIA_VIABILITY / G0 (Core leg) green; G1-G2 in progress
- Packet: INTEGRATION-A -> INTEGRATION-B/C transition
- State: partial
- Commit: ce9f4cd

## What changed
- PHASE A (restore buildability) COMPLETE:
  - Static audit + local Windows Swift 6.3.3 toolchain found the true historic
    CI breakers. Core Tests is GREEN on Apple CI for the first time ever:
    run 32432643757 / job 96627330329 at be45a41 (macos-26).
  - Key root causes: DownloadTask.state private(set) mutation from another
    file; URLSession not Sendable in corelibs Foundation (HTTPPerforming
    witness); FoundationNetworking types off-Darwin; unlabeled tuple
    witnesses; missing stub initializers; DownloadState Hashable +
    finalizationFailed/extractionFailed cases.
  - Local toolchain: .swift-toolchain/ (gitignored) built from official
    6.3.3 bundle via dark.exe + lessmsi; junctioned SDK stdlib/shims/XCTest/
    Testing into toolchain layout; LOCALAPPDATA override for platform
    discovery. `swift test --sdk <Windows.sdk>` = 55 tests, 0 failures.
- PHASE B/C slices landed (0a0683f, 2ea2acc, f94e34d):
  - Background URLSession reattachment after relaunch (getAllTasks grouping,
    handler re-registration, coordinator.attach keying fix, async reconcile).
  - Typed download failures end to end (@Observable lastFailure, user-safe
    messages, in-flight UI state, alert surface in VideoPageView).
  - App shell hardening: no try! container, idempotent remote commands,
    demo button/PlaceholderView removed, SpyTarget compile fix.
  - First-download finalization fixed: moveItem into empty destination
    (replaceItemAt requires existing destination — would have failed every
    first download).

## Acceptance evidence
- Core Tests run 32432643757 conclusion=success (observed via GitHub API).
- Local: swift build + swift test green on Windows Swift 6.3.3 strict mode.
- iOS CI run 32432643650 (be45a41) failed before slice commits; rerun with
  slices + step-summary diagnostics in flight at ce9f4cd.

## Known failures or deferred items
- ios-ci app-target compile status unknown at ce9f4cd (run in flight);
  failures now publish to the public step summary for diagnosis.
- Live YouTubeKit smoke tests not yet run (need macOS CI or device).
- Simulator E2E flows not yet exercised.

## Durable decisions made
- none (no ADR-level deviations)

## Exact next waypoint
- Read ios-ci run for ce9f4cd; fix reported app-target errors until
  xcodebuild test passes; then simulator smoke of 4 tabs + download flow.

## Resume commands
```bash
curl -s "https://api.github.com/repos/quantdale/FocusTube/actions/runs?per_page=5"
# job page summary readable via check-runs API output.summary when present
cd "/c/Users/Michael Roy/Documents/FocusTube" && export PATH="$PWD/.swift-toolchain/toolchain/usr/bin:$PWD/.swift-toolchain/flat/rtl/SourceDir:$PATH" && export LOCALAPPDATA="$PWD/.swift-toolchain/AppData/LocalApp" && swift test --sdk "$PWD/.swift-toolchain/flat/windows/SourceDir/LocalApp/Programs/Swift/Platforms/6.3.3/Windows.platform/Developer/SDKs/Windows.sdk"
```
