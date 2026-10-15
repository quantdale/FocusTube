# ROADMAP — Phase 1 Assessment (2026-10-15)

This is an assessment roadmap, not a new execution campaign. It does not
override `.agent/STATE.yaml` or `docs/13-ROADMAP.md`. Nothing here was
started in this pass.

## Where the project stands
Milestones M0–M8 plus the DDV2, HARDENING_V3, and OPT_PERFORMANCE_V1 campaigns
are recorded as complete. Qualified code SHA (re-qualified 2026-10-16): `23b0d2f`. `main` tip:
`47515e4` (docs-only). Older lineage: `7a70943` → `3fbf1d8` (perf) → `f345958` (CI).

## Definition of feature-complete (V1)
V1 is feature-complete only when all of these are true:
1. The `docs/00-PRODUCT-SPEC.md` primary jobs 1–8 work on a physical iPhone
   with a real Google account: Home feed, search, native playback, downloads
   at 1080/720/480/360, comments/replies, subscribe/like/playlists, resume,
   and offline playback.
2. Shorts policy invariants hold on device: no Shorts surfaces or routes,
   items of 180 s or less hidden, no autoplay-next, explicit Load more.
3. Background download, background audio, lock screen and Control Center,
   PiP, and headset controls pass on device (Batch A A1–A14).
4. One authenticated opt-in live-smoke CI dispatch is green.
5. Core Tests and the iOS CI fail-closed Gate are reliably green on `main`,
   with no known flaky tests.
6. No open Critical/High defects. Medium/Low items are logged in
   `.agent/HARDENING_BACKLOG.md`.

Current status: items 1–4 are unverified (owner-only), and item 5 is
**currently violated** (see BLOCKERS B1).

## Prioritized roadmap
| P | Item | Who | Notes |
|---|------|-----|-------|
| ✅ P0 | (Done in PR #1) Fix the flaky `testSubscriptionFeedChunksVideosListBeyondIDCap` (concurrent-hydration request order) so `main` is green again | agent | Linux repro: 10/40 failures. Assert on the set or sort of batches, or record batch index; production result order is already index-keyed. |
| ✅ P0 | (Done: `8448140` green) Re-qualify: green Core Tests and iOS CI on the new tip, then move the qualified baseline from `7a70943` | agent + CI | `3fbf1d8` changed app code after qualification. |
| P1 | Owner `DEVICE_VALIDATION_V1_REFRESHED`: Batch A A1–A14 | owner (Mac + iPhone) | See MAC_FINALIZATION_CHECKLIST.md |
| P1 | One authenticated live-smoke dispatch (`ios-ci.yml`, `live_smoke=true`) | owner | Checks that YouTubeKit 0.4.8 still extracts against current YouTube |
| P2 | Triage any Batch A failures (Batch B re-test) | agent | Fix only evidence-backed defects |
| ✅ P2 | (Done in PR #4: actions on v7; `aws/tap` warning absent, see DECISIONS) CI maintenance: Node 20 action deprecation (checkout/cache/upload-artifact v4 to current), Homebrew tap-trust warning | agent | Warnings today; they could turn into failures |
| P3 | YouTubeKit pin review: 0.4.8 is from Aug 2026; check upstream if live smoke fails | agent | Locked: upgrade only with evidence |
| P3 | HB-031 (sequential playlist walk) / HB-032 (polling settle) | product decision / agent | Deferred by design |
| ✅ P4 | (Closed 2026-10-16: narrative refreshed; adapter dirs kept by decision, see DECISIONS) Repo hygiene: consolidate agent-adapter dirs, refresh the stale narrative in `docs/13-ROADMAP.md` ("Active now — INTEGRATION_COMPLETION_V1") | agent | Low |
