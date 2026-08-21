# Checkpoint — PERSONAL_RELEASE_CANDIDATE (IC-EXIT passed)

- Date: 2026-08-21 ~15:05Z
- Branch: main
- HEAD: 16ad839 (both CI workflows green on this exact commit)
- Terminal durable state: `personal_release_candidate`

## Observed evidence (this campaign's exit gate)

- Core Tests workflow: run 32494119089 — success on 16ad839.
- ios-ci workflow: run 32494119169 / job 96808390721 — success on 16ad839.
  - Build (Debug): success.
  - Unit tests (FocusTubeTests, app-hosted on simulator): success,
    Gate recorded `unit=0`.
  - UI tests (FocusTubeUITests/LaunchTests): success, Gate recorded
    `ui=0` ("Test Suite 'All tests' passed").
  - Final Gate step (honest-verdict mechanism): success at 15:02:36Z.
- Local Windows Swift 6.3.3: 67 XCTest + 11 swift-testing, 0 failures.

## What the validation phase fixed (chronological)

1. f3db8e9 — split unit/UI test steps with per-test execution allowances and
   watchdog annotations; killed the historical 55-minute test-phase hang
   (both legs now finish in 1–4 minutes).
2. b83d0b3 — watchdog scripts ran under GitHub's default `bash -e`: no-match
   greps and failed `wait` aborted them before exit-code files were written;
   Gate saw "missing". Also made DownloadManager's validator injectable so
   fake-transfer tests can bypass the real AVFoundation seam.
3. 43bab86 — MediaAssetValidator made public (default-argument visibility).
4. e993a37 — stray closing parens from a scripted edit broke the test-bundle
   build; caught by the new watchdog annotations.
5. 076f39f — annotation prioritization: targeted `error: -[...]` assertions
   now precede generic grep so host-app CoreData noise cannot consume the cap.
6. 16ad839 — ROOT CAUSE of the four DownloadServiceTests failures: fixtures
   wrote files before creating their directory chain (NSCocoaError Code=4
   thrown from test body). Pre-existing bug, invisible in every earlier run
   because continue-on-error masked real results before exit-file
   instrumentation existed.

## Hardening delivered across the campaign

All Medium backlog items implemented (a9c8c70..f609cd3): Now Playing
publishing, store generation tokens, reattach event buffering + progress
seeding, AppDependencies hoist, strict per-task event ordering, storage
admission estimation, AVFoundation validation seam, cancellation-aware wait,
callback ordering, muxing-orphan sweep, ADR-0006 per-quality media layout,
persistence failure logging, duplicate-extraction removal. Low batch
implemented or explicitly dispositioned in HARDENING_BACKLOG.md.

## Remaining work — owner only (PERSONAL_RELEASE_CHECKLIST.md)

1. Apple signing + install on the physical iPhone (section 1).
2. Real Google OAuth client configuration + first live sign-in (section 2).
3. Device-only verifications: PiP, background audio under suspension,
   lock-screen/Bluetooth controls, genuine suspension download, radio
   transitions (section 3).

No agent implementation work remains. A fresh session should treat this
checkpoint as terminal unless the owner reopens scope.
