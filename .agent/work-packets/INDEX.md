# Work Packet Index

`.agent/STATE.yaml` records current reality, `.agent/WAYPOINTS.yaml` records machine-readable dependencies/status, and `.agent/EXECUTION_PROMPT.md` is the planner-to-executor campaign directive when marked `Status: ACTIVE`.

## Active campaign — HARDENING_V3_SYSTEMIC_DEBT_CLOSURE

Primary campaign packet: `H3-CAMPAIGN.md`
Execution prompt: `.agent/EXECUTION_PROMPT.md`
Executor entry: `/goal continue`

Execute continuously in this order unless current evidence proves a dependency-safe deviation:

1. H3-00 — truth reset, repository identity/isolation verification, debt audit ledger, durable state transition.
2. H3-01 — YouTube API taxonomy/decoding/protocol/input-validation hardening.
3. H3-02 — download state/retry/storage/failure-ownership hardening.
4. H3-03 — persistence truthfulness, deterministic ordering, metadata fidelity/state restoration.
5. H3-04 — render-path/database/formatter performance cleanup.
6. H3-05 — UX state machines, quota discipline, accessibility and draft/input preservation.
7. H3-06 — deterministic test-gap closure.
8. H3-07 — mandatory whole-repository systemic re-audit after known debt is consumed.
9. H3-08 — full regression and exact-SHA automated qualification.
10. H3-EXIT — backlog/state/waypoints/checkpoint reconciliation and refreshed DEVICE_VALIDATION handoff.

**Do not stop after one workstream passes.** H3 ends only at H3-EXIT or a true `AGENTS.md` stop condition.

## Downstream owner-only campaign

`DEVICE_VALIDATION_V1_REFRESHED` remains pending after H3. Physical-iPhone Batch A, real OAuth/device behavior, and the authenticated opt-in live-smoke are external evidence and must never be fabricated. Their absence does not block deterministic H3 engineering.

## Historical implementation packets

The implementation and earlier hardening/spec-closure packets remain historical evidence and should not be reopened without a new proven regression:

1. `WP-000-BOOTSTRAP.md` — reproducible project + remote simulator CI.
2. `WP-001-EXTRACTION.md` — YouTubeKit local extraction adapter.
3. `WP-002-PLAYBACK.md` — native online playback viability.
4. `WP-003-COMBINED-DOWNLOAD.md` — combined-stream background download/offline playback.
5. `WP-004-ADAPTIVE-1080.md` — adaptive 1080p video/audio + native mux proof.
6. `WP-005-DURABLE-DOWNLOAD-MANAGER.md` — persistence/relaunch/retries/reconciliation.
7. `WP-006-AUTH-DATA-API.md` — GoogleSignIn boundary + typed YouTube API client.
8. `WP-007-HOME-SHORTS-FIREWALL.md` — subscription feed + hard focus filtering.
9. `WP-008-SEARCH.md` — quota-aware explicit-submit search.
10. `WP-009-VIDEO-COMMENTS-ACTIONS.md` — video page/comments/account actions.
11. `WP-010-LIBRARY.md` — history/resume/offline management.
12. `WP-011-BACKGROUND-MEDIA.md` — PiP/audio/Now Playing/remote commands.
13. `WP-012-HARDEN-RELEASE.md` — completed release hardening.
14. `DDV2-CAMPAIGN.md` — completed SPEC_CLOSURE_DAILY_DRIVER_V2 systemic convergence.

## Blocked packet behavior

When a packet is partially blocked:

- continue unblocked acceptance criteria inside it;
- continue dependency-independent safe work where possible;
- record the precise blocked criterion/evidence in durable state;
- never pretend a blocked gate passed;
- escalate only when no useful safe work remains.

## Coordination and repository isolation

A single coordinator owns `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, checkpoints, campaign status and final integration. Subagents may work only in explicitly disjoint code/test scopes and may not race-write global state.

Every fresh worker must verify repository root, remote, branch and HEAD before writes. Never reuse state/worktrees/prompts from another repository and never allow another repository's agent to mutate FocusTube.

## New packet rule

Create a new packet only when unplanned work is large enough to need an independent acceptance boundary. Small discoveries stay inside the active H3 packet or are recorded in `.agent/HARDENING_BACKLOG.md` if genuinely deferred after H3 review. Use `TEMPLATE.md` for future standalone packets.
