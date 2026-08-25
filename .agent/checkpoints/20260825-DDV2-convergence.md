# DDV2 Convergence — Red-Gate Root Cause & Repair (2026-08-25)

## Trigger

iOS CI run `32712931724` (aebae44, run #157) ended **Gate failure** while the
step summary showed Build/Unit/UI all "green". The campaign handoff hypothesized
an aggregate-Gate orchestration defect. Re-inspection proved otherwise.

## Root cause (verified from check-run annotations + jobs API)

- The two bounded test steps (`Unit tests (FocusTubeTests)`,
  `UI tests (FocusTubeUITests)`) run under `continue-on-error: true` so both
  bundles always execute and diagnostics always publish.
- The final **Gate** honestly restores the verdict by reading
  `Artifacts/unit.exit` / `Artifacts/ui.exit` and failing unless both are `0`.
  Annotation: `iOS CI gate failed (unit=65 ui=65)`.
- Therefore the aggregate logic was **never defective** — real failures were
  hidden behind green step badges (fail-closed working as designed).

## Real defects behind the red gate

### Unit (app target) — download promotion double-count

`DownloadService.promoteQueuedWork()` budget guard counts
`activeLogicalCounts().active + promotingIDs.count`. A promoted job stayed in
`promotingIDs` for its whole transfer even after admission, when the persisted
`.resolving` record already carries the slot — a settled sibling could then
never promote.

- `DurableQueueTests.testSettlePromotesOldestQueuedJobFirstAndExactlyOnce`
  ("remaining queued job should be promoted")
- `DownloadServiceTests.testCancelFreesSlotAndPromotesQueuedDownload`
  (old version also asserted deferral with only one slot busy)

Fix: `promotingIDs.remove(id)` immediately after admission in `runOnce`;
cancel-frees-slot test rewritten to fill BOTH slots before asserting deferral.
(An earlier wave had already fixed `DownloadManagerTests` expectations for the
admitted-transfers-persist-.resolving semantics.)

### UI journeys — iOS 26 scroll synthesis + contract coupling

Five journeys failed on taller DDV2 layouts. Evidence across runs #157/#158:
frames of below-fold controls never moved despite up to 16 swipes; keyboard-
driven auto-scroll (journey K's composer) was the only reliable scroll path;
the simulator window band reports as `{{0,135.5},{402,603}}`.

Fixes:

1. Reveal machinery rotates three gesture strategies per attempt: container
   element swipe (.fast), explicit coordinate press-drag with momentum,
   app-level swipe (.fast). Failure traces now carry frame breadcrumbs and the
   scroll-container size.
2. Bounded last-resort clamped coordinate tap for tap-probes whose stable frame
   lies inside the physical screen — cannot fabricate a pass because callers'
   observable post-conditions remain the verdict.
3. Journey E asserts label/enabled/rendered contracts directly (video page is a
   deliberate non-lazy ScrollView: existence == rendered), no longer gated on
   gesture scrolling.
4. Journeys G/L wait for the transfer to settle (`waitForDownloadSettle`)
   before switching tabs, removing the registration race behind
   "rows=0" failures.
5. Journey K scrolls the composer back into view before typing the reply.

## CI hardening

`scripts/ci/verify-gate-contract.sh` + a new `Gate contract self-check` step in
ios-ci.yml structurally assert the fail-closed verdict restoration, so any edit
that weakens the Gate fails CI even when tests pass. Verified locally.

## Local validation at authoring time

- Windows Swift 6.3.3: `swift test` → 113 XCTest + 11 swift-testing, 0 failures.
- Parse checks on all edited Swift files; workflow structure checks green.

## Remaining gate

Green Core Tests + green iOS CI on the convergence commit (DDV2-10/11 exit).
