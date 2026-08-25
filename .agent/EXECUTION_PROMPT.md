# FocusTube Execution Prompt — HARDENING V3 Systemic Debt Closure & Release Convergence

Status: COMPLETE
Completed: 2026-08-26 — final code SHA `7a70943`; Core Tests run 32891558919 SUCCESS
and iOS CI run 32891558884 SUCCESS at that SHA (fail-closed Gate, Build Debug/Release,
Unit 141 XCTest, journeys 20/20). All HB-015..HB-030 resolved with evidence-backed
dispositions; whole-repository re-audit documented in
`.agent/work-packets/H3-AUDIT-LEDGER.md` (H3-07 section). Checkpoint:
`.agent/checkpoints/20260826-H3-SYSTEMIC-DEBT-CLOSURE.md` (truthful red-leg root
causes for runs #188..#195 included). DEVICE_VALIDATION baseline refreshed to 7a70943;
Batch A A1-A14 and one authenticated opt-in live-smoke remain pending external
owner-only evidence.
Planned-From: `01e1eeb2c6d14ad480631a224ba718acfe026023`
Target-Branch: `main`
Campaign: `HARDENING_V3_SYSTEMIC_DEBT_CLOSURE`
Executor entry: `/goal continue`

## Mission

Take FocusTube from the post-DDV2 automated-green baseline into a materially cleaner, more internally consistent, release-ready state by closing the remaining agent-actionable hardening debt **and auditing the systemic consequences of every change across the entire repository**.

DDV2 is terminal. Do not reopen its completed red-gate work unless new evidence proves a regression. Physical-iPhone Batch A and the opt-in live-smoke remain real owner-only downstream validation, but they do **not** block deterministic engineering work: `.agent/HARDENING_BACKLOG.md` currently contains HB-015..HB-030, including multiple Medium correctness/truthfulness/performance issues plus Low UX/test gaps. This campaign owns that work.

This is not a ticket-burning exercise. For every backlog item, inspect the model/API/view/store that contains it, every meaningful caller, downstream consumer, persistence/lifecycle interaction, and tests. A local edit is incomplete if it creates drift elsewhere. Also perform a fresh repository-wide audit after the known backlog is consumed; fix newly found Critical/High issues immediately and bounded high-value Medium issues before exit.

The repository/GitHub state is authoritative. If `main` moved beyond Planned-From, reconcile first and skip genuinely landed work rather than overwriting it.

## Planning evidence

At campaign planning time:

- `main` docs tip: `01e1eeb`; last code baseline: `05a80af`.
- DDV2 execution prompt is terminal; checkpoint: `.agent/checkpoints/20260825-DDV2-SYSTEMIC-CONVERGENCE.md`.
- Green qualification baseline at `05a80af`: Core Tests run `32855544250` SUCCESS and iOS CI run `32855544105` SUCCESS, including fail-closed Gate `unit=0 ui=0` and full journey set.
- Stability evidence: second consecutive green leg at docs tip `b5c3cea`, Core Tests `32859271508` and iOS CI `32859271422` SUCCESS.
- No open GitHub issues or pull requests were found during planning.
- `.agent/HARDENING_BACKLOG.md` has HB-015..HB-030 open; HB-013/HB-014 are recorded resolved.
- Direct code inspection confirms representative debt is still live: YouTube 403 mapping collapses most denials into `.quotaExceeded`, ISO8601 formatters are allocated inside decode maps, and `DownloadState` still exposes a transition table/dead statuses that require reconciliation with event paths.
- `.agent/BOOT_PROMPT.md` was stale at planning time (DEVICE_VALIDATION-only / zero-open-debt language) and must agree with this campaign after the planning commit.

## Non-negotiable execution model

1. **Deep impact audit, not narrow changed-file review.** For each change, inspect how it affects the entire codebase and complete product behavior.
2. **One coordinator owns global state.** Subagents may investigate or implement disjoint scopes, but they must not race-write `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, campaign/checkpoint files, or shared coordination artifacts.
3. **Repository isolation.** Operate only inside the FocusTube repository/worktree selected for this campaign. Before writes, verify repository root, remote, branch, and HEAD. Never reuse another repository's state/prompt/worktree or allow a worker targeted at another repo to mutate FocusTube.
4. **Do not weaken tests to obtain green.** User-observable contracts, fail-closed CI, focus/Shorts invariants, and truthful failure states remain the verdict.
5. **Continue autonomously.** A completed workstream is a transition point, not a stop. Stop only at H3-EXIT when no safe ready agent-actionable work remains, or when a true repository stop condition is evidenced.

## Ordered workstreams

### H3-00 — Truth reset, baseline, and debt verification

Before broad edits:

- fetch/prune origin; verify repo root, remote, branch, HEAD, clean/dirty worktree, and incoming commits;
- read `AGENTS.md`, `.agent/PLANNER_HANDOFF.md`, this prompt, `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, `.agent/AUTONOMOUS_EXECUTION.md`, `.agent/OPERATING_CONTRACT.md`, `.agent/HARDENING_BACKLOG.md`, DDV2 checkpoint/campaign packet, governing product/acceptance docs, and relevant tests;
- inspect current GitHub Actions status for the actual starting SHA and preserve the green baseline unless evidence says otherwise;
- verify every HB-015..HB-030 item against current code before editing; mark already-fixed items only with evidence;
- update durable campaign state so HARDENING_V3 is the active agent-actionable campaign while DEVICE_VALIDATION remains downstream owner-only evidence;
- establish a compact audit ledger mapping each HB item to affected code, callers/consumers, tests, migration/lifecycle implications, and intended disposition.

### H3-01 — YouTube API contract, decoding, taxonomy, and protocol integrity

Own HB-015, HB-016, HB-018, HB-019, HB-021 and the API portions of HB-030.

Audit the complete path from `YouTubeAPI` protocol → `YouTubeDataClient` request/response/error mapping → Home/Search/Video/Library stores → user-facing degraded/error/retry copy.

Requirements:

- split quota exhaustion from permanent forbidden/permission denials using evidence from supported YouTube error envelopes/status fields/reason strings; preserve comments-disabled handling and a deliberate malformed-envelope fallback;
- ensure UI copy and retry affordances distinguish transient quota/network problems from non-retryable permission failures;
- standardize non-empty resource-ID validation before wire calls for subscription/rating/playlist/comment-read/mutation paths where appropriate, with typed `.invalidInput` behavior;
- decide explicitly whether partial-page skip-and-continue decoding is safer than all-or-nothing for malformed individual items; if adopted, make the behavior deterministic, observable, tested, and non-silent; if rejected, record why and close only with evidence that current strictness is intentional;
- remove runtime-only protocol-extension traps where a missing production conformer override can compile and fail only on user action; prefer protocol decomposition or required methods without destroying useful deterministic fakes;
- cache RFC3339/ISO8601 parsers and support fractional seconds without hiding malformed required fields;
- add exact request-shape/page-token/error-envelope regression tests, including commentThreads pagination and relevant HB-030 edge cases;
- review every caller after taxonomy/protocol changes so switches remain exhaustive and user messaging truthful.

### H3-02 — Download state-machine, retry durability, storage admission, and failure ownership

Own HB-017, HB-022, HB-023 and any newly exposed download-model drift.

Audit end-to-end:

`DownloadState` / retry policy → coordinator → manager → service → persisted `DownloadRecord` / queued metadata → background transport/mux/finalization → DownloadsView/video page/player → relaunch/reconciliation.

Requirements:

- prove which `DownloadStatus` values are reachable in real event paths and persisted rows; either route mutations through the explicit transition model and test the transition table, or remove/deprecate dead states safely after migration compatibility is proven;
- no direct status assignment may bypass invariants merely for convenience; if exceptional reconciliation paths require it, encode and test that rule explicitly;
- persist enough duration/planning metadata for failed-row retries to re-run storage admission truthfully; use additive SwiftData evolution only and preserve old-row compatibility;
- ensure retry/cancel/reconcile/queue-promotion/free-space accounting remain correct after schema/model changes and no signed media URL becomes durable;
- move asynchronous/background download failures to an owning presentation surface so stale `lastFailure` cannot appear later on an unrelated video page; define clear consumption/clearing semantics;
- add regression tests for migration/defaults, failed-row retry with low storage, relaunch/reconcile, valid/invalid transitions, and stale failure ownership;
- re-run the existing durable-queue and fixture/offline-playback regression cluster after changes.

### H3-03 — Persistence truthfulness, ordering, metadata fidelity, and state restoration

Own HB-020, HB-025 and the persistence/library/navigation portions of HB-029/HB-030.

Audit SwiftData container lifetime and every save/delete path used by history, saves, recents, downloads, playlists/local summaries, plus consumers that optimistically mutate UI state.

Requirements:

- define truthful save-failure semantics: do not show durable success indefinitely when SwiftData save failed; use bounded rollback, surfaced degraded-persistence state, or another tested design that preserves session usability without lying about durability;
- audit delete snapshot/rollback paths for the same contract;
- make OfflineLibraryPolicy ordering deterministic with explicit tie-breakers and tests for equal timestamps, empty channel titles, negative sizes, and grouping ties;
- preserve enough summary metadata when reconstructing video pages from Library/playlists so channel actions and descriptions do not disappear merely because navigation originated from persisted/local data; evolve models additively and tolerate older rows;
- make TabView selection/restoration explicit if the audit confirms current implicit behavior loses the user's location across meaningful app lifecycle transitions;
- test custom recents maxEntries below existing count and save-failure/relaunch behavior;
- inspect all downstream UI after model additions to avoid duplicate fetches, stale snapshots, or migration crashes.

### H3-04 — Render-path performance and allocation discipline

Own HB-027 plus the performance implications of HB-021/HB-025/HB-029.

Do not micro-optimize blindly. Measure/trace structurally obvious hot paths and remove known N×full-fetch patterns.

Requirements:

- eliminate per-`VideoCard` main-thread full-history scans by computing/injecting a videoID→resume-fraction projection at the owning render/store layer;
- cache expensive date/relative-date formatters where lifetime/thread-safety is valid;
- verify playback progress invalidation does not trigger repeated full SwiftData table scans across Home/Search/Library/Downloads;
- audit AsyncImage/loading behavior and list identity for unnecessary rework introduced by non-lazy Search or DDV2 projections without regressing accessibility/XCUITest stability;
- add focused deterministic tests where logic moves into projection helpers; use Instruments only if available and useful, never fabricate measurements.

### H3-05 — UX state machines, quota discipline, accessibility, and input preservation

Own HB-024, HB-026, HB-028 and the remaining HB-029 UX batch.

Audit Home, Search, Video, Library/playlist detail, Downloads, Settings/auth and shared cards as interacting flows, not isolated screens.

Close at least:

- tri-state download-quality lifecycle copy: loading/resolving vs failed vs genuinely no supported qualities;
- reply-target switching must not silently destroy an in-progress draft; preserve per-target draft or require an explicit discard decision with deterministic tests;
- expose continue-watching percentage meaningfully to VoiceOver without breaking natural labels/identifiers used by journeys;
- nil/invalid thumbnails should reach a bounded placeholder/failure state rather than spin forever;
- prevent redundant identical Search submissions during flight and duplicate playlist/sign-in requests with pre-await gates; keep explicit submit and quota discipline intact;
- PlaylistDetail error state needs a real retry affordance and generation/stale-response protection;
- sign-in/re-entry and fake-session degraded states must be truthful rather than silent no-ops;
- bring remaining interactive targets to >=44pt where feasible, hide decorative chevrons from accessibility, and add useful sibling identifiers/hints to watch-history rows;
- reconcile continue-watching visibility thresholds across surfaces;
- malformed share IDs must surface a controlled error rather than sharing `file:///` garbage;
- re-audit keyboard/focus behavior after any Search/composer change; do not disturb the DDV2 evidence-driven retain-focus + scroll-dismiss contract without stronger evidence.

### H3-06 — Deterministic test-gap closure and invariant tables

Own HB-030 and test debt discovered while fixing H3-01..05.

Add cheap, high-signal coverage for:

- commentThreads pageToken plumbing;
- out-of-range resume indices and deterministic restart behavior;
- OfflineLibraryPolicy negative-size/empty-title/tie cases;
- recents custom-cap trimming;
- DownloadState valid/invalid transition table and reconciliation exceptions;
- 403 error-envelope taxonomy and resource-ID validation;
- migration/default behavior for new persisted fields;
- persistence save failures/rollback/degraded-state behavior;
- duplicate-submit and generation-token races;
- accessibility values/identifiers where deterministic unit/view-contract tests exist.

Prefer table-driven tests. Do not inflate UI-test scope for logic that can be proven below XCUITest.

### H3-07 — Whole-repository systemic re-audit after known debt closure

After the HB list is consumed, inspect the entire codebase again in light of the changes. This is mandatory.

Cover, at minimum:

- dependency composition/lifetime and scene/app lifecycle;
- every SwiftData model and migration-sensitive field;
- auth restore/sign-out/token boundaries and fake/live separation;
- YouTube API request taxonomy, pagination, quota, duplicate-submit and stale-response behavior;
- download queue/admission/retry/reconciliation/cancel/finalize/delete/storage accounting and filesystem divergence;
- player/local-vs-network selection/background media/Now Playing/PiP seams available to automation;
- Home/Search/Library/Video shared-model assumptions and navigation-origin fidelity;
- Shorts filtering-before-render and `/shorts/` route rejection everywhere, no autoplay-next, no infinite scroll;
- loading/empty/error/retry/degraded/offline states on every primary surface;
- Dynamic Type/VoiceOver/traits/hints/focus order/44pt targets/status-not-color-only semantics;
- actor/MainActor/Sendable/reentrancy/task cancellation/stale-response races;
- render-time database work, formatter/image churn, accidental unbounded collections;
- privacy/secrets/logging/debug fixture isolation/release configuration;
- XcodeGen/Package/CI reproducibility and fail-closed gate integrity;
- tests that assert implementation details instead of observable contracts.

For every finding: Critical/High => fix before proceeding. Medium => fix if bounded/high-value for daily reliability; otherwise record with specific evidence and rationale. Low => record only if it remains real after the campaign. Do not manufacture debt to keep the campaign alive.

### H3-08 — Regression convergence and release qualification

After implementation:

1. run the cheapest complete local matrix available on the host;
2. run focused suites for every changed subsystem before relying on the aggregate suite;
3. push coherent code commits to `main` so the Apple CI plane evaluates the exact code SHA;
4. inspect both Core Tests and iOS CI results/artifacts; the fail-closed Gate must be genuinely green (`unit.exit=0`, `ui.exit=0`);
5. if red, root-cause from artifacts/logs and repair the actual product/harness defect—never mask it;
6. repeat formerly flaky UI/fixture journeys enough to distinguish convergence from a lucky pass when practical;
7. re-run secrets/config, Shorts/focus-mode, persistence/offline, release-build and fixture-isolation checks;
8. obtain at least one full green qualification leg for the final code SHA; if the campaign touched broad UI/harness behavior, prefer a second consecutive green leg before exit.

Do not leave default `main` red.

### H3-EXIT — Durable reconciliation and owner-validation handoff

Only after no known Critical/High agent-actionable defect remains and automated gates are green:

- mark HB-015..HB-030 resolved/deferred with exact evidence and do not leave contradictory “open debt = none” prose;
- reconcile `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, `.agent/work-packets/INDEX.md`, the H3 campaign packet, README/release docs as needed;
- record a detailed H3 checkpoint with starting/final SHAs, root causes, migrations, tests, exact workflow run IDs, residual debt and external-only unknowns;
- refresh the DEVICE_VALIDATION baseline to the final post-H3 **code** SHA (docs-only tips do not replace it);
- preserve physical-iPhone Batch A A1-A14 and opt-in authenticated live-smoke as pending unless actually observed; never fabricate owner/device/account evidence;
- set this prompt to `Status: COMPLETE` only after the above is true;
- commit/push the final durable-state reconciliation with a detailed session report so a fresh `/goal continue` can resume truthfully.

## Locked constraints / invariants

Preserve governing repository decisions:

- native iOS; minimum iOS 17; Swift 6; SwiftUI;
- `FocusTubeCore` remains platform-neutral and free of UIKit/SwiftUI/AVKit/AVFoundation/SwiftData/GoogleSignIn/YouTubeKit imports;
- YouTubeKit remains local-only behind `MediaExtracting`;
- no yt-dlp, remote extractor, backend, or FFmpeg fallback without accepted ADR;
- download ladder exactly 1080/720/480/360; no manufactured absent tier;
- background URLSession transport and durable download truthfulness remain intact;
- additive/safe persistence migration only; no destructive store reset as a “fix”;
- Shorts blocked before render/navigation; no Shorts UI/route/vertical consumption mechanics;
- autoplay-next off; pagination explicit, not infinite;
- no real credentials/tokens/private responses in repo/tests/logs; no automated real Google-login flow;
- no force-push or destructive shared-history rewrite;
- repository instructions must remain general-purpose: do not hard-code a model, vendor, specific coding harness, or machine-specific executor assumption.

## Acceptance gates

HARDENING_V3 is complete only when all are true:

- HB-015..HB-030 have evidence-backed dispositions and no known Critical/High agent-actionable defect remains;
- Medium fixes that affect persistence/download/API truthfulness are covered by regression tests and caller/consumer audits;
- whole-repository systemic audit H3-07 is documented, not implied from changed-file review;
- all touched persistence changes are additive/backward-tolerant;
- API taxonomy, duplicate-submit, stale-response, download state/retry, persistence failure and ordering edge tests are green;
- primary UI surfaces have truthful loading/error/degraded states and no known accessibility blocker introduced by the campaign;
- Shorts/focus invariants, no-autoplay-next, explicit pagination, privacy/secrets, release-build and fixture isolation remain intact;
- final code SHA has green Core Tests and fully green iOS CI including the fail-closed Gate;
- durable state/docs/backlog/checkpoint agree on the final reality;
- DEVICE_VALIDATION is handed a refreshed final code baseline while owner-only evidence remains explicitly pending;
- repository ends clean and synchronized with `origin/main`.

## Git and reporting discipline

- Reconcile remote state before each major write wave; never overwrite newer mainline work.
- Prefer coherent commits by subsystem/workstream; do not mix unrelated refactors.
- Subagents do not push global-state updates independently; coordinator integrates them.
- Every substantial commit message must describe what changed, why, validation performed, and known residual risk when relevant.
- At campaign exit, the final commit message/checkpoint must function as a detailed session report: starting SHA, final code SHA, major root causes/fixes, migrations, tests/CI run IDs, debt disposition, external blockers, and exact next waypoint.
- Push at the end of the session/campaign so the next planner/executor can read the durable result from GitHub.

## Stop conditions

Do not stop because one workstream is done, because device validation is unavailable, or because tests are currently green. Stop only when:

- H3-EXIT is satisfied and no safe ready agent-actionable work remains; or
- a true blocker fits `AGENTS.md` escalation policy and blocks all useful safe work.

If blocked, record attempted mitigations, evidence, and the smallest required human action before stopping.
