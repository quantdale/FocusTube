# HARDENING_V3 Audit Ledger (H3-00)

Verified 2026-08-25 at `main` = `a581f38` (code baseline unchanged at `05a80af`).
Every HB-015..HB-030 item was re-inspected against current code before any edit;
none has silently landed. This ledger maps each item to implementation sites,
callers/consumers, test impact, migration/lifecycle implications, and intended
disposition. Dispositions update per workstream as evidence lands.

## Baseline truth at campaign open

- Repo identity: quantdale/FocusTube, branch main, HEAD a581f38 = origin/main, clean tree.
- Local Windows matrix: swift build clean; swift test 118 XCTest + 11 swift-testing, 0 failures.
- Hosted CI at a581f38 (docs-only tip): Core Tests run 32863980246 SUCCESS; iOS CI
  run 32863980094 launched on push (docs-only; pointer convention applies).
- Code qualification baseline remains 05a80af (Core Tests 32855544250 / iOS CI 32855544105,
  both SUCCESS) until the first H3 code commit refreshes it.
- gh unauthenticated on this host (re-checked); live-smoke dispatch stays owner-gated.

## Ledger

### HB-015 (Medium) — 403 taxonomy conflates denials with quotaExceeded — LIVE
- Code: YouTubeDataClient.swift:308-324 (`apiError(from:statusCode:)` only special-cases legacy
  `errors[].reason == "commentsDisabled"`; all other 403 -> `.quotaExceeded`). New-style
  `error.status == "PERMISSION_DENIED"` envelopes fall through.
- Callers/consumers: VideoActionsService, CommentsService, HomeFeedStore/SearchStore error copy
  sites (RootView, SearchView, VideoPageView) render retry affordances keyed off quota semantics.
- Tests: YouTubeDataClientTests.testQuota403EnvelopeWithoutCommentsDisabledReasonStaysGeneric pins
  current conflation — must be re-authored with the new taxonomy, not weakened.
- Migration: none (pure enum case addition; Equatable exhaustiveness audited via compiler switches).
- Disposition: fix in H3-01 — typed `.forbidden` for permanent permission denials
  (403 non-quota reasons incl. PERMISSION_DENIED status), keep quota reasons mapped to
  `.quotaExceeded`, deliberate malformed-envelope fallback; UI copy distinguishes retryable vs not.

### HB-016 (Low) — all-or-nothing page decoding — LIVE
- Code: YouTubeDataClient.swift:87-93 (`decode` throws over whole response), all page models strict.
- Decision required by prompt: adopt deterministic skip-and-continue per item OR record why
  strictness stays. Current callers treat a failed page as surface-wide failure.
- Disposition: decide in H3-01 from evidence; if adopted, log skipped-count via os.Logger and pin
  with table tests; malformed-envelope fallback stays typed `.decode`.

### HB-017 (Medium) — DownloadState dead statuses + untested transition table bypassed — LIVE
- Code: DownloadState.swift:74-104 table exists; DownloadCoordinator writes status directly at
  cancel (:138 apply), `.failed` event (:264), complete() (:426), fail() (:435); begin()/finalize()
  use transition(to:). No event path ever enters `.waitingForRetry`/`.reResolving` (grep-verified);
  app-layer DownloadService owns retry without those states.
- Callers/consumers: DownloadRecord.statusRaw round-trips raw values; DownloadsView phase labels
  include waitingForRetry/reResolving copy that cannot occur; reconciler maps persisted rows.
- Tests: no DownloadState table tests exist (only PlaybackState).
- Migration: persisted rows could carry dead rawValues only if they ever were written — never were;
  safe to deprecate/remove after confirming zero writers, or route writes through transitions.
- Disposition: fix in H3-02 — make coordinator event-path writes go through legal transitions,
  add full transition-table test, remove/justify dead statuses (keep Codable decode tolerance for
  old rows).

### HB-018 (Low) — inconsistent pre-network resource-id validation — LIVE
- Code: YouTubeDataClient subscribe(:137)/unsubscribe(:147)/rateVideo(:153)/findMySubscription(:203)/
  fetchMyVideoRating(:218)/addToPlaylist(:261)/removeFromPlaylist(:272) take ids unguarded;
  comments paths validate text+parentID first.
- Disposition: fix in H3-01 — shared non-empty guard -> `.invalidInput`, wire-shape regression tests.

### HB-019 (Low) — protocol-extension default traps — LIVE
- Code: YouTubeAPI.swift:131-161 eight throwing defaults (`unknown(status:-1)`).
- Consumers: production client implements all; UITestFixtures fake implements its needed subset.
- Disposition: fix in H3-01 — remove defaults so conformers must implement (compiler-enforced),
  updating fakes deliberately; keep read-path fakes explicit rather than silent.

### HB-020 (Low) — OfflineLibraryPolicy tie-order claims exceed guarantees — LIVE
- Code: OfflineLibraryPolicy.swift:33-49 sorted() claims stability but uses comparator without
  tiebreakers; groupedByChannel(:53-75) orders groups by max createdAt with equal-timestamp ties
  unordered across runs (dictionary + non-total comparator).
- Tests: OfflineLibraryPolicyTests cover primary orders, not ties/negative sizes/empty titles.
- Disposition: fix in H3-03 — explicit deterministic tiebreakers (videoID), total order comparators,
  edge tests (equal timestamps, empty channel titles, negative sizes, grouping ties).

### HB-021 (Low) — per-row ISO8601DateFormatter allocation; fractional seconds nil — LIVE
- Code: ISO8601DateFormatter constructed inside decode maps at YouTubeDataClient.swift:59 (details),
  :118/:127 (comments+replies), :486 (insert normalization). Default options reject fractional forms.
- Disposition: fix in H3-01 — cached static formatters (with + without fractional seconds), fallback
  chain; malformed required fields still fail decode as today.

### HB-022 (Medium) — shared lastFailure alert ownership — LIVE
- Code: DownloadService.lastFailure written from finish()/fail() for ANY settled run including queue
  promotions and background settlements; sole presenter VideoPageView.swift:97-100 (alert).
- Impact path: failure raised while Downloads/front-of-house settles -> next pushed video page pops
  stale unrelated alert.
- Tests: DownloadServiceTests assert lastFailure content (service-level contract stays valid);
  presentation ownership changes are UI-level.
- Disposition: fix in H3-02 — download failures present where they originate (Downloads surface
  badge/alert consuming-and-clearing), video-page alert scoped to its own start attempts; define
  clearing semantics + deterministic tests.

### HB-023 (Medium) — retry drops durationSeconds, skipping storage pre-check — LIVE
- Code: DownloadsView.swift:202-210 Retry calls download(...) without durationSeconds -> 0 ->
  StorageEstimator.requiredBytes == 0 -> pre-check skipped (DownloadService.runOnce:337-341 documents
  skip). DownloadRecord persists duration ONLY inside queuedMetadataData (:96-108); failed rows of
  non-queued origin have none.
- Migration: additive optional persisted field (lightweight SwiftData migration), old rows nil ->
  synthesize from queuedMetadata when present else estimate-unknown (status quo behavior).
- Disposition: fix in H3-02 — persist duration additively at enqueue, thread through retry; regression
  test failed-row retry performs storage admission when duration known.

### HB-024 (Low) — download-quality tri-state collapse — LIVE
- Code: VideoPageView.loadQualities:568-584 sets qualities=[] both before resolution completes and on
  extraction failure; picker copy reads single "no qualities" string either way.
- Disposition: fix in H3-05 — tri-state lifecycle (resolving / failed / genuinely-empty) driving picker
  copy; button disabled-state preserved.

### HB-025 (Medium) — SwiftData save failures logged-only while UI keeps optimistic state — LIVE
- Code: LibraryStore.save():287-293 logs fault; RecentSearchStore.persist():76-86 logs fault and keeps
  in-memory view. Mutations flip observable state BEFORE persistence outcome is known.
- Disposition: fix in H3-03 — truthful degraded-persistence signal (bounded design): write-through
  verification ordering + user-visible degraded indicator where durable loss would otherwise be
  silent; save/delete rollback audit; deterministic failure-injection tests.

### HB-026 (Low) — reply-target switch destroys draft — LIVE
- Code: VideoPageView replyTarget set at :550-551 clears composerText unconditionally; submit success
  path :713-735 clears properly.
- Disposition: fix in H3-05 — preserve per-target draft or explicit discard confirmation; deterministic
  view-model-level tests where possible.

### HB-027 (Medium) — per-card history scans + formatter churn — LIVE
- Code: RootView.swift:493 and SearchView.swift:62 call VideoCard.resumeFraction(videoID:history:
  library.history) inside row builders; library.history is a computed FULL-TABLE fetch evaluated per
  row per body evaluation; VideoCard.relativePublished constructs RelativeDateTimeFormatter per card
  per render (:110-116).
- Disposition: fix in H3-04 — compute videoID->fraction projection once per owning store/render pass;
  cache formatters (thread-safe usage on MainActor); verify progress invalidation does not rescan.

### HB-028 (Low) — continue-watching invisible to VoiceOver on cards — LIVE
- Code: VideoCard progress strip :64-76 decoration-only; comment :30-31 explicitly keeps natural
  children exposed (journey contracts depend on it).
- Disposition: fix in H3-05 — add accessibilityValue("x% watched") on the thumbnail/card element
  WITHOUT collapsing natural-child label composition; verify journeys unaffected.

### HB-029 (Low batch) — multiple UX edges — LIVE (each sub-item spot-checked)
- AsyncImage(nil URL) spins forever: VideoCard.thumbnail uses AsyncImage(url:) — nil URL never leaves
  .empty phase (failure branch only covers real-URL failures). Fix: bounded placeholder/failure glyph
  for nil URL.
- Playlist-origin summaries drop channelID/description: PlaylistDetailView:374-383 builds VideoSummary
  with nils (duration/published/thumbnail/description/channelID) — Subscribe hidden + no description
  when opened from playlist; same pattern suspected for Library-origin reconstructions (verify during
  H3-03; evolve persisted models additively).
- Playlists load lacks generation token: verify exact site during H3-05; add pre-await duplicate gate.
- PlaylistDetailView load-error has NO retry affordance: RootView.swift:367-368 renders Text(errorText)
  only (removalError DOES have Try again). Fix: real retry affordance + stale-response protection.
- Search submit enabled during flight: SearchView submit path lacks pre-await disable (generation guard
  holds correctness, quota burns). Fix with bounded duplicate-submit gate.
- Sign-in buttons lack re-entry guards; Settings sign-in silent no-op under fake sessions: RootView:459,
  AccountSettingsView:62 call signIn directly. Fix guards + truthful degraded states.
- Sub-44pt targets/decorative chevrons/history-row hints: sweep during H3-05.
- Continue-watching thresholds differ: VideoCard (0.01..0.99) vs Library rows (>0). Unify.
- TabView no selection binding/restoration: RootView TabView {:23 has no selection. Make explicit.
- Share fallback file:///: VideoPageView:340 `?? URL(fileURLWithPath: "/")`. Controlled error instead.

### HB-030 (Low) — residual deterministic-test gaps — LIVE (crossrefs)
- commentThreads pageToken plumbing through client (playlistItems analog tested): absent.
- Out-of-range numeric feed-resume index restart: covered indirectly? verify + pin explicitly.
- OfflineLibraryPolicy negative-size/empty-title/tie cases: absent.
- Recents custom maxEntries below existing count: policy covered partially; trim-below-cap case verify.
- Equal-timestamp tie ordering: absent.
- Disposition: close in H3-06 alongside regressions from H3-01..05 (table-driven, cheapest layer).

## Cross-cutting execution notes

- One coordinator (this session) owns STATE/WAYPOINTS/campaign/checkpoint edits.
- All persistence changes additive; no destructive resets; old-row tolerance pinned by tests.
- No test weakening: HB-015's existing generic-403 test gets re-authored to the new taxonomy with
  equal-or-stronger assertions; journey-affecting UI changes keep identifier contracts stable.
- CI plane: every code wave pushes to main; Core Tests + iOS CI Gate must be green at final SHA.
