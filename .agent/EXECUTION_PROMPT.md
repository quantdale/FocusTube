# FocusTube Execution Prompt — DDV2 Systemic Convergence & Ship-Readiness Closure

Status: COMPLETE
Completed: 2026-08-25 — final code SHA `05a80af`; Core Tests run 32855544250
SUCCESS and iOS CI run 32855544105 SUCCESS (fail-closed Gate, unit=0 ui=0).
Evidence checkpoint: `.agent/checkpoints/20260825-DDV2-SYSTEMIC-CONVERGENCE.md`.
Deferred Medium/Low debt recorded as HB-015..HB-030 in
`.agent/HARDENING_BACKLOG.md`. Remaining external evidence (owner-only):
DEVICE_VALIDATION Batch A on the physical iPhone against the refreshed
baseline 05a80af, plus one opt-in live_smoke dispatch.
Planned-From: `dfb939b6bd3675ebd07ddc93f568b55057ca6494`
Target-Branch: `main`
Campaign: `DDV2-SYSTEMIC-CONVERGENCE-QUALIFICATION`
Executor entry: `/goal continue`

## Mission

Take the repository from its current **DDV2 implementation-complete-but-red** state to a **truthful, systemically audited, automated-gates-green daily-driver release baseline**.

This is not a one-bug campaign. Do not stop after repairing the two currently visible UI failures, after one passing test, or after one narrow diff review. The DDV2 wave changed multiple product and infrastructure surfaces across downloads, Search, Home/video cards, video actions/comments, settings, Library/playlists, persistence, playback, API boundaries, fixture infrastructure, accessibility, and CI. Audit how those changes interact with the rest of the application and close the highest-value remaining engineering defects before DDV2 exits.

The current repository/GitHub state is authoritative over stale narrative prose. Reconcile before editing.

## Current evidence at planning time

- `main` HEAD: `dfb939b6bd3675ebd07ddc93f568b55057ca6494`.
- DDV2 is 36 commits ahead of campaign-open baseline `934dc69`.
- Core Tests run `32828052886` at current HEAD: **SUCCESS**.
- iOS CI run `32828052990` at current HEAD: **FAILURE**. Build Debug, Build Release, Unit tests, UI-test step wrapper, diagnostics publication, and gate-contract self-check completed, but the final fail-closed Gate correctly restored `ui.exit=65` (`unit.exit=0`).
- The iOS CI artifact shows two concrete XCUITest failures:
  1. `testOfflinePlaybackReachesPlayingStateWithFixtureMedia` — fixture media generation surfaced `FixtureMedia Code=4`, the scripted transport degraded to a 4-byte fallback, and local playback displayed `Playback failed` instead of reaching the `player-playing` marker.
  2. `testSearchButtonSubmitsAndShortsNeverAppear` — after explicit Search submit the text field remained keyboard-focused; the keyboard compressed the list and `load-more-button` could not be revealed after the bounded swipe attempts. The test comment currently claims submit drops focus, while `SearchView.submit()` has no explicit focus-state control: treat this as a behavior/test-contract drift to resolve deliberately, not by weakening the assertion.
- `.agent/STATE.yaml` and `.agent/WAYPOINTS.yaml` show DDV2-00 through DDV2-09 complete, DDV2-10/11 in progress, DDV2-EXIT pending.
- `.agent/work-packets/DDV2-CAMPAIGN.md` narrative packet statuses are stale relative to `WAYPOINTS.yaml`; reconcile durable docs before exit.
- GitHub has no open issues and no recent PRs to merge; `main` is the working line.
- External-only validation remains real: physical-iPhone Batch A and one opt-in live-smoke run must never be fabricated or treated as automated proof.

## Scope

This campaign owns:

1. current red-gate root cause and deterministic repair;
2. regression and interaction audit of **all DDV2-touched subsystems**;
3. impact audit across the **rest of the codebase**, especially lifecycle, persistence, navigation, concurrency, offline behavior, background media, auth, focus/Shorts invariants, accessibility, error/degraded states, privacy/security, CI and release plumbing;
4. test-harness reliability where failures can mask product truth;
5. durable state/docs/checkpoint reconciliation;
6. automated release qualification and truthful handoff to refreshed device validation.

Do not invent new unrelated product scope. Do not perform cosmetic churn merely because it is available. Fix reproducible correctness/reliability/ship-readiness problems and high-value UX/A11y defects that affect the DDV2 daily-driver goal.

## Ordered workstreams

### W0 — Reconcile and establish truth

Before edits:

- fetch/prune origin;
- inspect branch, HEAD, `origin/main`, worktree, untracked files, and any incoming commits;
- read `AGENTS.md`, `.agent/PLANNER_HANDOFF.md`, this prompt, `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, `.agent/OPERATING_CONTRACT.md`, `.agent/HARDENING_BACKLOG.md`, active DDV2 packet/checkpoint files, and governing product docs;
- inspect the current implementation and tests rather than trusting status labels;
- inspect latest GitHub Actions state and, for any red run, its jobs/artifacts/log evidence;
- if HEAD moved beyond Planned-From, reconcile this plan against landed work and skip anything already genuinely fixed.

Do not reset/cherry-pick away newer mainline work.

### W1 — Close the current red iOS gate without test weakening

#### W1A — Offline playable fixture failure

Root-cause why `FixtureMediaFactory` can remain non-completed (`FixtureMedia Code=4`) on the macOS 26/iOS 26 CI runner.

Audit the entire path, not just the throwing line:

`FixtureMediaFactory` → `ScriptedDownloadTransport` → download coordinator/manager/service → final-media validation/indexing → DownloadsView row → local player → AVPlayer state marker.

Requirements:

- deterministic CI-compatible fixture media must be genuinely decodable/playable;
- do not silently convert encoder failure into a product-success path with opaque filler bytes;
- failure diagnostics may remain useful, but a fallback must not create a fake “completed download” that only fails later during playback;
- preserve Release isolation: fixture-only machinery remains structurally unavailable in production builds;
- preserve final-media validation semantics rather than bypassing them for tests;
- add/adjust the cheapest deterministic coverage necessary to make recurrence obvious before the full XCUITest journey.

Do not assume the existing AVAssetWriter recipe is the only valid fixture strategy. Choose the simplest reliable solution that preserves the product contract and repository invariants.

#### W1B — Search focus / load-more interaction failure

Resolve the Search submit/focus contract deliberately.

Audit:

- `SearchView` explicit button submit and keyboard Return submit;
- recent-search/suggestion flows that call the same submit path;
- retry behavior;
- keyboard dismissal and later refocus ability;
- result-list geometry and explicit Load more accessibility on iOS 26;
- XCUITest helpers/reveal logic only after product behavior is correct.

The final behavior must allow results and `Load more` to remain usable after submit **and** allow the user/test to focus the search field again for subsequent searches. Prefer explicit SwiftUI focus-state ownership over global responder hacks if that proves more reliable, but derive the implementation from evidence.

Do not “fix” this by increasing swipe counts indefinitely, coordinate-tapping hidden controls, or deleting the behavioral assertion.

### W2 — DDV2 regression-cluster audit

Systematically review the DDV2 delta from `934dc69` to current `main`, including interactions among:

- durable queued downloads, FIFO promotion, retry, cancellation, recovery, reconciliation and projection caches;
- Downloads queue/storage/sorting/grouping/offline playback UI;
- comment/reply mutation APIs and account actions;
- VideoPage action row, composer, save-to-playlist, download and navigation;
- Account/Settings sign-in/out and local-data preservation;
- shared `VideoCard` use on Home/Search/Library continuity surfaces;
- Search recents/suggestions and explicit-submit quota discipline;
- Library history/saves/playlists/additive persistence metadata and migration tolerance;
- local playback, Now Playing/background-media wiring and offline guarantees;
- DEBUG fixture architecture and XCUITest journeys;
- iOS CI fail-closed gate contract.

For each subsystem, inspect callers and downstream consumers outside the changed file. Look for stale assumptions, duplicated state, lifecycle gaps, races, impossible states, swallowed persistence failures, navigation/focus breakage, accessibility regressions, and tests that prove implementation details instead of user-observable contracts.

Fix every clearly reproducible Critical/High issue immediately. Fix high-value Medium ship-readiness defects when bounded and safe. Log only genuinely nonblocking residual Low debt with evidence.

### W3 — Whole-codebase impact audit

Do not limit review to recently modified files. Perform a repository-wide ship-readiness audit **in relation to the DDV2 changes and the complete product contract**.

At minimum cover:

- app composition/dependency lifetime and scene/app lifecycle;
- navigation stack/sheets, tab transitions and state restoration;
- SwiftData model/container creation, additive migration behavior, save/delete/reconcile error paths and offline durability;
- download state-machine invariants, event ordering, cancellation, relaunch, partial/corrupt file cleanup, capacity accounting and no signed-URL persistence;
- player state, local-vs-network media selection, failure recovery, PiP/background/Now Playing seams that can be automated;
- auth restore/sign-out/token boundaries, YouTube API error mapping, mutation idempotency/duplicate-submit behavior and scope minimization;
- Home/Search filtering-before-render, `/shorts/` blocking, no Shorts UI/routes, no autoplay-next and no infinite-scroll regressions;
- explicit Load more behavior and quota discipline;
- empty/loading/error/retry/degraded/offline states for all primary tabs and new DDV2 surfaces;
- Dynamic Type, VoiceOver labels/hints/traits, 44pt interactive targets, focus order, keyboard behavior and status-not-color-only semantics;
- concurrency/MainActor/Sendable correctness, stale-response races, reentrancy and task cancellation;
- memory/performance hotspots caused by new projections/cards/images/persistence reads, without speculative micro-optimization;
- privacy/security/secrets/logging, fixture isolation and release-build configuration;
- XcodeGen/package/workflow reproducibility and generated-file hygiene.

The objective is not “find something in every category”; it is to prove each category was actually inspected and either fix or record evidence-backed findings.

### W4 — Test architecture and flake hardening

The recent history contains repeated UI/fixture convergence commits. Treat persistent flakes as a reliability defect, not noise.

- separate product defects from harness defects using logs/xcresult/artifacts;
- keep assertions on user-observable postconditions;
- use stable accessibility identifiers and bounded waits;
- remove brittle gesture/coordinate dependence where product structure can expose a stable semantic interaction;
- never change `continue-on-error`/Gate behavior to hide a failing bundle;
- never weaken a test solely to obtain green CI;
- add targeted regression tests for every product defect fixed in this campaign;
- when practical, repeat previously flaky focused tests enough times to show convergence before relying on one full-suite pass.

### W5 — Automated qualification

After code fixes and audits:

1. run the full cheapest local matrix available on the current host;
2. push coherent commits to `main` so GitHub Actions executes the Apple build/test plane;
3. inspect **both** Core Tests and iOS CI for the exact final code SHA;
4. if either is red, inspect artifacts/logs, fix the actual cause, push, and repeat;
5. require a fully green iOS CI Gate at the final code SHA — green wrapper steps with nonzero `unit.exit`/`ui.exit` are not acceptance;
6. verify Debug and Release builds, unit suite, UI journeys, gate-contract self-check, secrets/config hygiene and focus-mode invariants;
7. where tooling permits, obtain additional repeated evidence for the formerly flaky journeys/CI rather than declaring stability from a single lucky pass.

Do not stop on a red default branch.

### W6 — Durable truth, DDV2 exit, and downstream handoff

Once automated engineering is genuinely complete:

- reconcile `.agent/WAYPOINTS.yaml`, `.agent/STATE.yaml`, `.agent/work-packets/DDV2-CAMPAIGN.md`, `.agent/HARDENING_BACKLOG.md`, README/release docs where necessary;
- remove contradictions such as narrative packet statuses that still say `pending` for landed work;
- record exact final code SHA and exact green workflow run IDs;
- create a detailed checkpoint for this systemic convergence/qualification campaign;
- refresh the DEVICE_VALIDATION baseline to the final post-DDV2 code SHA;
- preserve physical-device Batch A and live-smoke items as **pending external evidence** unless actually observed;
- never fabricate OAuth, physical-device, PiP/background-suspension, signing, Bluetooth/lock-screen, or live-YouTube results;
- mark this `EXECUTION_PROMPT.md` `Status: COMPLETE` (or otherwise make the prompt unambiguously terminal per repository conventions) only after the automated gates and durable-state reconciliation pass.

If the whole-codebase audit finds further agent-actionable implementation/hardening work required for safe daily use, continue and close it before DDV2-EXIT. External owner-only validation is not a reason to leave deterministic engineering work unfinished.

## Constraints / locked invariants

Preserve all governing repository decisions, including:

- native iOS, minimum iOS 17, Swift 6, SwiftUI;
- `FocusTubeCore` remains platform-neutral and free of Apple UI/media/persistence/auth framework imports;
- YouTubeKit remains local-only behind `MediaExtracting`;
- no yt-dlp, remote extractor, backend or FFmpeg fallback without an accepted ADR;
- allowed download ladder exactly 1080/720/480/360; do not manufacture missing tiers;
- background download transport and durable state semantics remain truthful;
- Shorts blocked before render/navigation; no Shorts tab/shelf/vertical swipe;
- autoplay-next remains off; pagination remains explicit rather than infinite;
- no real credentials in tests or repository; no automated real Google-login flow;
- additive/safe persistence migration only;
- no force-push and no destructive history rewrites;
- no model-, harness-, or vendor-specific assumptions in repository instructions.

## Acceptance gates

This campaign is complete only when **all** of the following are true:

- current confirmed iOS CI failures are root-caused and fixed without weakened behavioral guarantees;
- both previously failing journeys pass on the Apple CI plane;
- the DDV2 regression-cluster audit is completed across all touched subsystems and their callers/consumers;
- the broader repository impact audit is completed and evidence/findings are recorded;
- no known Critical/High agent-actionable defect remains open;
- final `main` code SHA has green Core Tests and fully green iOS CI including the fail-closed Gate;
- focus/Shorts, privacy/secrets, persistence/offline and release-build invariants are rechecked;
- durable state/docs reflect reality and no stale DDV2 status contradiction remains;
- device-validation baseline points at the final post-DDV2 code SHA;
- only truly external physical-device/live-account/live-smoke evidence remains pending;
- repository ends clean and `main` is synchronized with `origin/main`.

## Git and reporting requirements

- Work from current `main`; fetch/prune before starting and before final handoff.
- Use coherent, testable commits; do not bundle unrelated cleanup.
- Push completed work to `origin/main`; never force-push.
- After every substantive push, inspect hosted CI and continue until actionable failures are fixed.
- Final commit/checkpoint reporting must be detailed enough for a fresh agent to recover without chat history: starting SHA, final SHA, root causes, files/subsystems changed, tests run, workflow run IDs/results, audit findings fixed/deferred, remaining external blockers, and exact next transition.
- Do not output a new pasteable “next prompt” as the work product. Execute this campaign through repository state and `/goal continue` semantics.

## Stop condition

Stop only when there is no safe agent-actionable engineering work remaining for this campaign, the final automated gates are green, durable repository truth is synchronized, and the remaining evidence is genuinely external owner/device/account validation. Otherwise keep going.