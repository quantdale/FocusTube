# SPEC_CLOSURE_DAILY_DRIVER_V2 — Campaign Packets

Opened 2026-08-24 by owner directive. Predecessor campaigns (IMPLEMENTATION_V1,
HARDENING_V1/V2, FINAL_COMPLETION_V1) are complete; DEVICE_VALIDATION_V1
(owner-executed physical-device Batch A) remains downstream external validation.
Any substantive product change in this campaign means the eventual
device-validation baseline must be refreshed — the old `42f761a` baseline is
NOT reused after this campaign lands product changes.

## Motivation (owner-recorded discrepancies under audit)

- G6/documentation claims top-level comment/reply posting; API boundary appears read-only for comments.
- `AccountActionsService` has subscribe/unsubscribe/rating, but production UI exposure is unverified.
- Product spec expects an account/settings surface; existence unverified.
- docs/07 expects thumbnails/duration/publish info on Home cards; rendering unverified.
- docs/07 expects recent-search suggestions; implementation unverified.
- Library docs expect playlists/storage management; implementation unverified.
- Downloads docs expect richer queue management/sorting/storage behavior.
- G7 "storage usage/UI" evidence may not represent genuine storage management.
- STATE.yaml claims no open debt while HB-013/HB-014 remain open.

Rule: where the locked product spec requires the capability and it is technically reasonable — IMPLEMENT it. Where a historical requirement should genuinely be dropped — record evidence and decision explicitly. Never silently edit history.

## Packet order

| id | scope | status |
|---|---|---|
| DDV2-00 | Truth reset: audit every claim above against code; write findings into checkpoints; open campaign state | complete |
| DDV2-01 | Durable queued-download lifecycle (P0 correctness): queued jobs survive process death; FIFO promotion reconstructed from persisted records; no signed-URL persistence; cancel works queued; corrupt rows degrade to recoverable failure | complete |
| DDV2-02 | Download management/storage/retry completion: queue controls UX, offline library sorting/size/channel grouping + total storage usage, retry-policy reconciliation (docs say up to 3 attempts; code ships 1), human-readable phases | complete |
| DDV2-03 | Typed account/comment API expansion: commentThreads/comments insert, subscription resource-id retrieval for truthful unsubscribe, rating get/set/remove models | complete |
| DDV2-04 | Video action/comment UI: rich metadata, action row (save/like/subscribe/share/download), composer with typed failure states, duplicate-submit prevention | complete |
| DDV2-05 | Account/settings surface: profile/settings screen, sign-in/out state handling, storage link, privacy/version info | complete |
| DDV2-06 | Shared rich video-card system + Home rebuild (thumbnail/title/channel/published/duration, accessibility, Dynamic Type, caching) | complete |
| DDV2-07 | Search recents/rich results: persisted deduped bounded recent queries, local suggestions per keystroke (no remote calls typing), shared cards | complete |
| DDV2-08 | Library/history/playlists/storage: continue-watching upgrades, richer additive SwiftData metadata, supported-playlists reconciliation | complete |
| DDV2-09 | HB-013 closure (projection architecture) + HB-014 closure (local playable test fixture) if not already closed en route | complete |
| DDV2-10 | Accessibility/visual integration pass across all new surfaces | complete |
| DDV2-11 | Full regression/release qualification: full suites, both workflows green, secrets audit, focus-mode invariant audit, docs sync | complete |
| DDV2-EXIT | Campaign evidence checkpoint + handoff to refreshed DEVICE_VALIDATION | complete (2026-08-25, baseline 05a80af; Batch A/live-smoke remain owner-executed) |

Statuses are authoritative in `.agent/WAYPOINTS.yaml`; this file carries the narrative scope.

## Hard invariants (unchanged)

No Shorts tab/shelf/route/vertical swipe; filtering before render; no autoplay-next;
no infinite scroll; download ladder exactly 1080/720/480/360; no yt-dlp/remote
extractor/backend/FFmpeg without accepted ADR; Core stays platform-neutral; typed
API boundaries only; never leak tokens; migrations additive and safe.
