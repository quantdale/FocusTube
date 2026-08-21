# Checkpoint — Hardening backlog closure (HB-011 / HB-012)

Date: 2026-08-22
Code commit: 03ce6f6 (`fix(hardening): close remaining HB-011/HB-012 backlog items`)
Docs commit: (this commit)
Campaign: INTEGRATION_COMPLETION_V1 — terminal state `personal_release_candidate` retained;
this packet closed the last open Medium/Low debt recorded during HARDENING_V1.

## What changed (commit 03ce6f6)

- HB-011a (Medium): table-driven malformed-payload coverage for all five decoding
  endpoints of `YouTubeDataClient` (truncated / wrong-typed field / missing required
  field / unexpected envelope), malformed 403 error-body fallback-to-status mapping,
  commentsDisabled 403-envelope detection driven through `CommentsService`, and a
  quota-reason negative control. Detection already existed in `apiError`; tests only.
- HB-011b (Medium): new deterministic app-layer store tests —
  `FocusTubeTests/SearchStoreTests.swift` (5), `FocusTubeTests/HomeFeedStoreTests.swift` (3):
  typed failure surfacing, spinner settling, auth-class failures retaining prior content,
  generation-guard stale-response protection. Park-and-release `CallGate` actor fakes with
  hard arrival deadlines (regressions fail instead of hanging CI). No production seams needed.
- HB-012 remainder (Low):
  - `DownloadCoordinator`: per-event unstructured Tasks replaced by lock-guarded
    completion-node chains (arrival order preserved, O(1) tail retention); transport
    handlers capture `[weak self]`. New regression suite
    `DownloadCoordinatorEventOrderingTests` pins aggregation under concurrent progress
    and failed-behind-in-flight-finalization ordering.
  - `BackgroundMediaCoordinator`: re-registration removes only its own `addTarget`
    tokens instead of blanket `removeTarget(nil)`.
  - `AppDependencies`: in-memory `ModelContainer` fallback no longer `try!`; logged
    fault + do/catch ladder with a contextual fatal last resort.
  - `DownloadRecord`: components decode failures log via os.Logger; payload bytes never logged.
  - `PlayerCoordinator` deinit teardown assumption stands as documented (app-lifetime
    instance under AppDependencies ownership); rationale recorded in backlog.
- Hygiene: `.gitignore` now excludes local CI-monitoring scratch (`.ci-*`).
- `.agent/HARDENING_BACKLOG.md`: HB-011 and HB-012 marked resolved with this commit reference.
  Backlog is now fully dispositioned — no open Medium/Low items remain.

## Acceptance evidence

- Core Tests workflow (Apple CI): run 32501838807 — **success** on 03ce6f6.
- iOS CI workflow (Apple CI): run 32501839603, job 96833085436 — **success** on 03ce6f6;
  steps observed green: Test FocusTubeCore, Generate Xcode project, Build (Debug),
  Unit tests (FocusTubeTests), UI tests (FocusTubeUITests), Gate (unit=0 / ui=0 semantics).
- Local Windows validation: unavailable this session (repo-local Swift 6.3.3 toolchain
  cannot link — MSVC CRT import libraries absent). All swarm output was instead verified
  line-by-line against actual sources (protocol shapes, init signatures, error mapping,
  store generation semantics) before commit; macOS CI is the authoritative gate per
  locked decision `apple_build_plane: github_actions_macos`.

## Remaining (owner-only, unchanged)

`PERSONAL_RELEASE_CHECKLIST.md` sections 1–3: Apple signing/install, real Google OAuth
configuration, device-only verifications (PiP, background audio, lock-screen/Bluetooth
controls, genuine suspension download). No agent implementation work remains open.
