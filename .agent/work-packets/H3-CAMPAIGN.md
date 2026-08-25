# HARDENING_V3_SYSTEMIC_DEBT_CLOSURE — Campaign Packet

Status: ACTIVE
Opened: 2026-08-25
Planned-From: `01e1eeb2c6d14ad480631a224ba718acfe026023`
Execution prompt: `.agent/EXECUTION_PROMPT.md`
Entry: `/goal continue`

## Why this campaign exists

DDV2 completed its automated engineering gate at code SHA `05a80af` with two consecutive green qualification legs, but its systemic audit intentionally deferred HB-015..HB-030 as nonblocking Medium/Low debt. Those items are now the highest-value safe agent-actionable work while physical-device Batch A and the opt-in live-smoke remain owner-only downstream validation.

The backlog clusters are not independent cleanups. They cross API taxonomy, protocol design, download state and retry durability, SwiftData persistence truthfulness, navigation-origin metadata, render-time database work, quota discipline, accessibility, input preservation, and deterministic test coverage. H3 therefore closes them as a system and then performs a fresh whole-repository impact audit before release handoff.

## Campaign packets

### H3-00 — Truth reset and audit ledger
- Verify repository identity/root/remote/branch/HEAD and clean state.
- Reconcile current `main` against Planned-From; never overwrite newer work.
- Read all governing agent/state/spec/checkpoint/backlog artifacts.
- Verify HB-015..HB-030 against code and tests.
- Transition durable state to HARDENING_V3 while retaining DEVICE_VALIDATION as downstream owner evidence.
- Produce an audit ledger mapping each debt item to implementation, callers/consumers, tests, persistence/lifecycle impact, and disposition.

### H3-01 — API contract and decode hardening
Owns HB-015, 016, 018, 019, 021 and API parts of 030.
- Typed 403 taxonomy beyond quota/commentsDisabled.
- Consistent pre-wire resource-id validation.
- Explicit partial-vs-strict item decoding decision.
- Remove protocol default traps.
- Cached fractional/non-fractional RFC3339 parsing.
- Pagination/request-shape/error-envelope regression tests and caller/UI copy audit.

### H3-02 — Download model and retry truthfulness
Owns HB-017, 022, 023.
- Reconcile real event paths with the explicit DownloadState transition table.
- Remove/prove dead statuses or route event paths through legal transitions.
- Persist duration/planning metadata additively for truthful failed-row storage admission on retry.
- Move asynchronous download failure presentation to the owning surface; eliminate stale unrelated alerts.
- Re-prove queue promotion, relaunch/reconcile, cancel, storage accounting, migration tolerance and offline playback.

### H3-03 — Persistence, ordering and metadata fidelity
Owns HB-020, 025 and persistence/navigation portions of 029/030.
- Truthful SwiftData save/delete failure semantics instead of silent optimistic durability.
- Deterministic tie ordering/grouping.
- Preserve channel/description metadata across Library/playlist-origin navigation with additive migration.
- Explicit tab/state restoration if the audit proves current loss.
- Edge tests for recents caps, tie ordering and old-row defaults.

### H3-04 — Render-path performance
Owns HB-027 and related allocation churn.
- Remove per-card full-history fetches; compute projections once per owning render/store layer.
- Cache expensive formatters safely.
- Audit playback-progress invalidation and image/list behavior for accidental repeated full-table work.
- Keep optimization evidence-driven; do not invent benchmark numbers.

### H3-05 — UX, quota and accessibility convergence
Owns HB-024, 026, 028 and remaining HB-029 UI items.
- Distinguish quality loading/failure/empty states.
- Preserve or explicitly confirm discard of comment/reply drafts.
- VoiceOver continue-watching progress.
- Bounded thumbnail failure state.
- Search/playlist/sign-in duplicate-submit guards and stale-response protection.
- Playlist retry affordance.
- Truthful fake/signed-out auth states.
- >=44pt targets where feasible; decorative AX cleanup; watch-history hints/identifiers.
- Unify continue-watching thresholds.
- Controlled malformed-share error.
- Preserve DDV2 Search keyboard/focus contract unless stronger evidence requires change.

### H3-06 — Deterministic test-gap closure
Owns HB-030 plus regressions discovered during H3.
- Table-driven edge coverage at the cheapest layer.
- Download transition validity, API taxonomy, pagination, migration defaults, persistence failures, duplicate-submit races and ordering.
- Do not move logic tests into XCUITest unnecessarily.

### H3-07 — Mandatory whole-repository re-audit
After known debt is closed, review the entire codebase in relation to the changed system:
- app/dependency lifecycle;
- all SwiftData models and migrations;
- auth/token boundaries;
- API quota/pagination/error/stale-response semantics;
- download queue/retry/reconcile/finalization/filesystem divergence;
- playback/background/PiP/Now Playing seams available to automation;
- cross-surface model/navigation fidelity;
- Shorts firewall/no-autoplay/no-infinite-scroll invariants;
- loading/empty/error/degraded/offline states;
- Dynamic Type/VoiceOver/focus/target sizing;
- actor/MainActor/Sendable/reentrancy/task-cancellation correctness;
- render-time persistence/allocation hot paths;
- privacy/secrets/debug fixture/release isolation;
- XcodeGen/package/CI fail-closed reproducibility;
- tests that overfit implementation instead of behavior.

Critical/High findings are fixed immediately. Bounded high-value Medium findings should be fixed before exit. Residual Low debt must be concrete and evidence-backed.

### H3-08 — Qualification
- Focused changed-subsystem tests first.
- Full local deterministic matrix available on host.
- Push code so macOS/iOS CI tests the exact final code SHA.
- Require Core Tests green and iOS CI fail-closed Gate genuinely green (`unit.exit=0`, `ui.exit=0`).
- Root-cause every red result from artifacts/logs; never hide failures.
- Re-run flaky-risk journeys enough to distinguish stability from luck when practical.
- Recheck Shorts/focus, secrets/config, release build, persistence/offline and fixture isolation.

### H3-EXIT — Durable handoff
- Every HB-015..HB-030 has an evidence-backed disposition.
- No known Critical/High agent-actionable defect remains.
- Whole-codebase audit is documented.
- Final code SHA has green automated qualification.
- Update STATE/WAYPOINTS/index/backlog/checkpoint/release docs to agree.
- Refresh DEVICE_VALIDATION baseline to final H3 code SHA.
- Leave physical-iPhone Batch A and authenticated live-smoke pending unless truly observed.
- Mark `.agent/EXECUTION_PROMPT.md` COMPLETE only at this gate.
- Final commit/checkpoint is a detailed session report and is pushed.

## Coordination and isolation

A single coordinator owns global state/checkpoint/campaign files. Subagents receive disjoint scopes and may not race-write shared state. Every worker must verify it is operating inside FocusTube's repository/worktree before writes; no cross-repository agent may reuse or mutate FocusTube state, and FocusTube workers may not touch another repository.

## Locked invariants

Preserve `AGENTS.md` and product decisions: native iOS/SwiftUI/Swift 6; platform-neutral FocusTubeCore; local YouTubeKit boundary; no yt-dlp/remote extractor/backend/FFmpeg fallback; exact 1080/720/480/360 ladder; background durable URLSession semantics; additive persistence only; Shorts blocked before render/navigation; no autoplay-next; explicit pagination; no real secrets/credential automation; no force-push; no model/vendor/harness-specific repository instructions.

## External evidence intentionally outside H3

- Physical iPhone DEVICE_VALIDATION Batch A A1-A14.
- Real Google OAuth exercise.
- Real-device PiP/background/lock-screen/Bluetooth behavior.
- One authenticated opt-in `live_smoke` workflow dispatch.

These remain pending unless actually observed. Their absence does not block deterministic H3 engineering.
