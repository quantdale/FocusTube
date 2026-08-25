# DDV2 Systemic Convergence & Ship-Readiness Closure (2026-08-25)

Campaign: `DDV2-SYSTEMIC-CONVERGENCE-QUALIFICATION` (executor prompt
`.agent/EXECUTION_PROMPT.md`, planned from dfb939b).
Final automated-gates-green code SHA: **`05a80af`**
(`fix(tests): bounded keyboard-dismissal retries; keyboard-safe drag origin…`).

## Starting state

- Planned-from `dfb939b`: iOS CI run 32828052990 FAILED behind continue-on-error
  display steps; Gate honestly restored `unit=0 ui=65`.
- Session reconciled origin first: fetched origin, fast-forwarded docs-only
  planning commit `2498ce9`, adopted the ACTIVE execution prompt.

## Red-gate root causes and repairs (W1)

### 1. Fixture media generation deterministically failed (`FixtureMedia Code=4`)

The aebae44 wave ("bounded fixture-media waits") replaced the original
semaphore-based completion wait but **dropped the `writer.finishWriting()` call
itself**. `markAsFinished()` only closes the input; without `finishWriting()`
the AVAssetWriter stays `.writing` forever, so every generation expired the
bounded wait with Code=4 — on every runner, deterministically.

Repairs (edae425):
- restored `finishWriting` with a bounded semaphore wait;
- removed the opaque 4-byte filler fallback in `ScriptedDownloadTransport`: a
  generation failure now degrades to the typed `.transportFailed` event so no
  fake "completed download" can ever register (the fallback previously created
  completed rows that only failed at playback);
- added `FocusTubeTests/FixtureMediaTests.swift`: unit-bundle regression pins
  asserting the master file is genuinely decodable (AVAsset video track +
  positive duration) and temp copies are distinct real-media files. Verified
  green in CI before any XCUITest journey ran.

### 2. Search focus / Load-more interaction (behavior/test-contract drift)

Evidence-driven contract settled across three runs:
- Programmatic blur on submit (both the earlier `UIResponder.resignFirstResponder`
  approach and `@FocusState = false`) left the field **un-refocusable by tap**
  on the iOS 26 simulator (run edae425: keyboards=0, retry tap ignored). Final
  behavior: submit RETAINS focus; any scroll gesture immediately dismisses the
  keyboard via `.scrollDismissesKeyboard(.immediately)`. Journey I (recents,
  which must re-focus) passed under this contract.
- A lazy `List` refused to realize the below-fold Load-more row while the
  keyboard compressed the viewport (run 8ad4c69: 18 attempts, empty frame
  breadcrumbs). SearchView converted to a deliberate NON-lAZY ScrollView with
  explicit section headers (same contract as DownloadsView/video page):
  existence equals render.
- While the keyboard is presented its glass swallows gestures originating in
  the lower screen (run 2eeaba6: target frame frozen at y=1160 across every
  attempt). Harness fixes: `dismissKeyboard` retries boundedly and verifies
  disappearance; `scrollOnce` drags from the safe top band while a keyboard is
  up. Journey D additionally performs one realistic user dismissal (nav-bar
  tap) before reveal. All behavioral assertions unchanged.

### 3. Offline playback paused mid-flight (journey L)

After the fixture fix, playback genuinely started but read `pstate=paused`:
the 15-frame fixture clip ran only 1.5 s and hit natural end-of-stream before
the first AX query. Fixture clip extended to 12 s (120 frames @10 fps), and the
local player sheet now owns a DEDICATED per-presentation `PlayerCoordinator`
instead of re-parenting the shared app controller (be8e1e4), eliminating
cross-surface player hijack/failure-state leakage. `PlayerView` exposes a live
`player-status` AX element plus an enlarged `player-playing` marker so future
failures are diagnosable without artifact access.

### Compile-break detour caught by the fail-closed plane

298a817 introduced two iOS-only compile errors (UIKit-named
`keyboardDismissMode`; `if let` shadowing a `@State`). Build (Debug) failed in
7m34s — the gate-contract plane caught them before any test ran; fixed in
46844a8.

## Audit slices executed (W2/W3)

Two parallel read-only audits covered the DDV2 delta (Core services + app
UI/persistence) plus targeted manual review of the download state machine,
gate-contract script, secrets/config hygiene, Shorts/autoplay invariants, and
fixture Release isolation.

Fixed immediately (Critical/High or bounded high-value Mediums):
- playlist-item removal no longer deletes rows on server failure (truthful
  removal + retry affordance) [H1];
- save-to-playlist duplicate-submit guard with per-row in-flight state [H2];
- duplicate-submit gates moved BEFORE the first await in like/subscribe/
  comment paths; composer field disabled during flight; posted-text snapshot [M1];
- subscribe success + failed verification no longer renders false unsubscribed
  state (explicit error surfaces instead) [M2];
- signed-out comments surface the authored sign-in degraded state instead of a
  fabricated "No comments yet." [M3];
- signed-out Subscribe behaves like Like (enabled, sign-in alert on tap) [M4];
- swipe-down dismissal of the local player stops playback (onDisappear stop) [M7];
- pagination dedupe by video id in SearchStore/HomeFeedStore (ForEach identity
  corruption risk) [M8];
- saved-section delete snapshots rows before mutating (index-shift hazard) [M9];
- ISO-8601 duration parser: day/week forms (P1DT2H30M0S / P2W), anchored regex,
  fractional floor — unknown-duration videos >24 h no longer skip storage
  admission pre-checks [Core Finding 3];
- wire-shape pins for subscribe/unsubscribe/rate request construction
  (AccountActionWireTests) [Core Finding 1];
- rateVideo copy-mutate quirk cleaned; VideoCard progress strip remains logged
  for a11y follow-up rather than destabilizing label-composition journeys.

Deferred with evidence → `.agent/HARDENING_BACKLOG.md` HB-015..HB-030 (all
Medium/Low, none blocking): 403 taxonomy conflation, all-or-nothing page
decode tradeoff, dead DownloadState statuses, pre-network id validation gaps,
protocol-default mutation seams, offline-policy tie-order claims, per-row
formatter/date churn, stale lastFailure alert ownership, retry-path duration
loss, picker state collapse, SwiftData save-failure UI truthfulness, composer
reply draft wipe, main-thread history scans, VoiceOver progress strip, low
UX/a11y batch, residual deterministic-test gaps.

## Invariant re-checks (W5)

- Secrets/config: only `.example` committed; real secrets file absent locally
  and gitignored.
- Shorts: zero new Shorts surfaces/routes; firewall tests green.
- Autoplay-next/infinite scroll: absent; pagination stays explicit.
- Core platform-neutrality: Foundation-only imports verified.
- Gate contract self-check green in every leg.
- Fixture machinery remains DEBUG-only (compiled out of Release).

## Final qualification evidence (exact runs at code SHA 05a80af)

- Core Tests run **32855544250**: SUCCESS.
- iOS CI run **32855544105**: SUCCESS — Debug+Release builds, unit suite
  (`unit.exit=0`, incl. 118 Core XCTest locally + app-target unit bundle),
  full UI journey set, gate-contract self-check, fail-closed Gate green
  (`ui.exit=0`).

Local Windows matrix during the campaign: `swift test` green throughout
(113→118 XCTest + 11 swift-testing, 0 failures).

Previously-failing journeys now pass: L (offline playing), D (search
submit/load-more), I (recents/refocus), plus the whole suite in the same leg.

## Remaining external evidence (unchanged, owner-only)

- DEVICE_VALIDATION_V1 Batch A items A1–A14 on the physical iPhone (baseline
  refreshed to 05a80af — 42f761a is NOT reused).
- One opt-in live_smoke workflow_dispatch (requires authenticated gh or manual
  Actions dispatch; anonymous API cannot POST the event; total_count of
  dispatch events remained 0 through this campaign).
