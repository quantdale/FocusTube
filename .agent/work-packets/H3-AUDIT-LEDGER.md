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

### HB-015 (Medium) — 403 taxonomy conflates denials with quotaExceeded — FIXED (H3-01)
- Code: YouTubeDataClient.swift:308-324 (`apiError(from:statusCode:)` only special-cases legacy
  `errors[].reason == "commentsDisabled"`; all other 403 -> `.quotaExceeded`). New-style
  `error.status == "PERMISSION_DENIED"` envelopes fall through.
- Callers/consumers: VideoActionsService, CommentsService, HomeFeedStore/SearchStore error copy
  sites (RootView, SearchView, VideoPageView) render retry affordances keyed off quota semantics.
- Tests: YouTubeDataClientTests.testQuota403EnvelopeWithoutCommentsDisabledReasonStaysGeneric pins
  current conflation — must be re-authored with the new taxonomy, not weakened.
- Migration: none (pure enum case addition; Equatable exhaustiveness audited via compiler switches).
- Disposition: FIXED in H3-01 — typed `.forbidden` case added; mapping order:
  commentsDisabled legacy reason -> commentsDisabled; quota reasons
  (quotaExceeded/dailyLimit/rateLimit/userRateLimit) or canonical status
  RESOURCE_EXHAUSTED -> .quotaExceeded; permission reasons
  (forbidden/insufficientPermissions) or canonical status PERMISSION_DENIED ->
  .forbidden; DELIBERATE fallback for unparseable/unrecognized 403 bodies stays
  .quotaExceeded (likeliest cause for this app + only safe retry guidance).
  Tests: PermissionDenied envelope, legacy-reason table incl. unknown-reason
  fallback, RESOURCE_EXHAUSTED canonical, permission-denial-does-not-masquerade-
  as-comments-disabled. UI: explicit .forbidden copy at all five error-label
  sites (comments/account actions/search/playlists/subscriptions feed).

### HB-016 (Low) — all-or-nothing page decoding — FIXED (H3-01, skip-and-continue adopted)
- Code: YouTubeDataClient.swift:87-93 (`decode` throws over whole response), all page models strict.
- Decision required by prompt: adopt deterministic skip-and-continue per item OR record why
  strictness stays. Current callers treat a failed page as surface-wide failure.
- Disposition: FIXED in H3-01 — ADOPTED deterministic per-item skip-and-continue
  across every list-bearing endpoint (subscriptions/playlistItems/videos/search/
  commentThreads/playlists lookups). Truthfulness bounds enforced and tested:
  (1) a list where EVERY item is malformed still throws .decode (no silent empty
  state); (2) partial skips are non-silent via injected onItemsSkipped observer,
  wired to os.Logger at AppDependencies composition; (3) top-level envelope
  fields remain strict. Tests: single-malformed-item skip + count reporting,
  all-malformed-throws-decode, pre-existing whole-payload malformed suite still
  green unchanged.

### HB-017 (Medium) — DownloadState dead statuses + untested transition table bypassed — FIXED (H3-02)
- Code: DownloadState.swift:74-104 table exists; DownloadCoordinator writes status directly at
  cancel (:138 apply), `.failed` event (:264), complete() (:426), fail() (:435); begin()/finalize()
  use transition(to:). No event path ever enters `.waitingForRetry`/`.reResolving` (grep-verified);
  app-layer DownloadService owns retry without those states.
- Callers/consumers: DownloadRecord.statusRaw round-trips raw values; DownloadsView phase labels
  include waitingForRetry/reResolving copy that cannot occur; reconciler maps persisted rows.
- Tests: no DownloadState table tests exist (only PlaybackState).
- Migration: persisted rows could carry dead rawValues only if they ever were written — never were;
  safe to deprecate/remove after confirming zero writers, or route writes through transitions.
- Disposition: FIXED in H3-02 — (1) dead `.waitingForRetry`/`.reResolving`
  statuses REMOVED (never written by any event path since WP-005;
  reconciler/cancel-guards/labels/active-filter updated; legacy persisted
  rawValues degrade via DownloadRecord's nil->.failed fallback, retryable as
  before); `.paused` retained (modeled + reconciler-handled concept).
  (2) ALL coordinator event-path writes route through legal transitions:
  cancel, .failed event handler, complete(), fail(); attach()/enqueue()
  documented as INITIALIZATION, exempt from the table.
  (3) NEW product-truth rule encoded + tested: a settled completion is FINAL —
  late/duplicate transport failures can no longer regress registered playable
  media into failed rows. The old last-terminal-wins expectation in
  EventOrderingTests pinned exactly this defect class; rewritten to assert
  serialization-without-regression — a strengthening against the drift.
  Tests: full transition-matrix table test, error rules, rejected-transition
  immutability, coordinator late-failure/cancel/fail pins.

### HB-018 (Low) — inconsistent pre-network resource-id validation — FIXED (H3-01)
- Code: YouTubeDataClient subscribe(:137)/unsubscribe(:147)/rateVideo(:153)/findMySubscription(:203)/
  fetchMyVideoRating(:218)/addToPlaylist(:261)/removeFromPlaylist(:272) take ids unguarded;
  comments paths validate text+parentID first.
- Disposition: FIXED in H3-01 — shared validatedResourceID guard applied to
  subscribe/unsubscribe/rateVideo/findMySubscription/fetchMyVideoRating/
  addToPlaylist(both ids)/removeFromPlaylist/fetchComments/fetchPlaylistVideoIDs/
  fetchPlaylistItems/postTopLevelComment(videoID); all map to typed .invalidInput.
  Test: table-driven no-network rejection across 12 call shapes.

### HB-019 (Low) — protocol-extension default traps — FIXED (H3-01, protocol decomposition)
- Code: YouTubeAPI.swift:131-161 eight throwing defaults (`unknown(status:-1)`).
- Consumers: production client implements all; UITestFixtures fake implements its needed subset.
- Disposition: FIXED in H3-01 — decomposed into `YouTubeReading` (5 read methods
  + required fetchSubscriptionFeed whose ONLY default is REAL composed logic,
  not a trap) and `YouTubeWriting` (11 mutation/lookup endpoints, no defaults);
  `YouTubeAPI` = Reading & Writing typealias keeps production signatures stable.
  Read-path stores/services narrowed (HomeFeedStore/SearchStore/HomeFeedAggregator/
  SearchService); read-only fakes narrowed conformance (7 fakes); full fakes
  (FixtureYouTubeAPI/FullStubAPI) implement everything explicitly — FullStubAPI
  was silently inheriting throwing defaults, proving the trap was live.
  Compiler now enforces every conformer implements what it claims.

### HB-020 (Low) — OfflineLibraryPolicy tie-order claims exceed guarantees — FIXED (H3-03)
- Code: OfflineLibraryPolicy.swift:33-49 sorted() claims stability but uses comparator without
  tiebreakers; groupedByChannel(:53-75) orders groups by max createdAt with equal-timestamp ties
  unordered across runs (dictionary + non-total comparator).
- Tests: OfflineLibraryPolicyTests cover primary orders, not ties/negative sizes/empty titles.
- Disposition: FIXED in H3-03 — every comparator is now TOTAL: explicit `id`
  ascending tiebreaker after primary keys in all three sort orders;
  groupedByChannel breaks equal newest-timestamp ties by case-insensitive
  channel display name. Stability claim replaced with a documented total-order
  guarantee. Tests: equal-timestamps-by-id across all orders incl. reversed
  input invariance, negative sizes with id tiebreak, empty/whitespace/named
  channel grouping, grouping tie on newest timestamp.

### HB-021 (Low) — per-row ISO8601DateFormatter allocation; fractional seconds nil — FIXED (H3-01)
- Code: ISO8601DateFormatter constructed inside decode maps at YouTubeDataClient.swift:59 (details),
  :118/:127 (comments+replies), :486 (insert normalization). Default options reject fractional forms.
- Disposition: FIXED in H3-01 — shared cached APIDate parsers (plain +
  fractional-second formatters, thread-safe instances, nonisolated(unsafe) under
  Swift 6 strict concurrency) replace per-item allocations at all publishedAt
  decode sites (details/comments/replies/insert-normalization); fractional forms
  now parse instead of silently nil'ing. Test: plain + .250Z fractional both yield
  non-nil dates through fetchVideoDetails.

### HB-022 (Medium) — shared lastFailure alert ownership — FIXED (H3-02)
- Code: DownloadService.lastFailure written from finish()/fail() for ANY settled run including queue
  promotions and background settlements; sole presenter VideoPageView.swift:97-100 (alert).
- Impact path: failure raised while Downloads/front-of-house settles -> next pushed video page pops
  stale unrelated alert.
- Tests: DownloadServiceTests assert lastFailure content (service-level contract stays valid);
  presentation ownership changes are UI-level.
- Disposition: FIXED in H3-02 — `lastFailure` is written ONLY for user-requested
  starts (origin threaded through run/runOnce/finish); queue-promotion failures
  log via os.Logger and surface where they belong: the Downloads failed section
  (persisted record projection, typed error, Retry row). The video-page alert
  can therefore never pop with a stale failure from an unrelated promoted or
  background settlement. VideoPageView presenter unchanged; acknowledgeFailure
  unchanged. Tests (app target): promoted-failure leaves lastFailure nil while
  failedTasks contains the row; user-request failure still writes it.

### HB-023 (Medium) — retry drops durationSeconds, skipping storage pre-check — FIXED (H3-02)
- Code: DownloadsView.swift:202-210 Retry calls download(...) without durationSeconds -> 0 ->
  StorageEstimator.requiredBytes == 0 -> pre-check skipped (DownloadService.runOnce:337-341 documents
  skip). DownloadRecord persists duration ONLY inside queuedMetadataData (:96-108); failed rows of
  non-queued origin have none.
- Migration: additive optional persisted field (lightweight SwiftData migration), old rows nil ->
  synthesize from queuedMetadata when present else estimate-unknown (status quo behavior).
- Disposition: FIXED in H3-02 — additive `plannedDurationSeconds: Double?` on
  DownloadRecord (lightweight migration; legacy rows read nil and keep the
  historical unknown-duration behavior), captured at enqueue via
  manager.enqueue(plannedDurationSeconds:), exposed via
  plannedDurationSeconds(taskID:), and threaded through DownloadsView Retry ->
  service.download(durationSeconds:) so failed-row retries re-run storage
  admission truthfully. No signed URLs persisted. Tests (app target):
  persist/read-back roundtrip; legacy-row nil; duration-carrying attempt on an
  always-full volume refuses typed storageRefused BEFORE any transfer begins.

### HB-024 (Low) — download-quality tri-state collapse — FIXED (H3-05)
- Code: VideoPageView.loadQualities:568-584 sets qualities=[] both before resolution completes and on
  extraction failure; picker copy reads single "no qualities" string either way.
- Disposition: FIXED in H3-05 — QualityResolutionState (resolving/failed/
  loaded) drives DownloadQualityPickerView copy: "Checking downloadable
  qualities…" / "Couldn't check… Try reopening this video." / genuinely-empty
  "No downloadable qualities for this video"; loaded-with-results renders the
  segmented picker as before. Download button stays disabled until loaded with
  results. Extraction failure now do/catch-typed instead of try? collapse.

### HB-025 (Medium) — SwiftData save failures logged-only while UI keeps optimistic state — FIXED (H3-03)
- Code: LibraryStore.save():287-293 logs fault; RecentSearchStore.persist():76-86 logs fault and keeps
  in-memory view. Mutations flip observable state BEFORE persistence outcome is known.
- Disposition: FIXED in H3-03 with a two-tier truthful design:
  Durability-critical data (offline download index): addDownloadedMedia rolls
  back insert/update mutations when save() fails (ALL prior field values
  restored) so the session never advertises a download whose durable row
  vanished.
  Session-tolerant data (history/saves): optimistic in-memory state kept for
  usability, but observable `isPersistenceDegraded` flips on failure and clears
  on next success — no silent durability claims; rationale recorded per the
  prompt's tested-design option.
  Recents: full write-through — entries advance only after persist succeeds;
  failed rewrites context.rollback() so broken transactions cannot resurrect.
  Injected save seam (`saveHandler:`) enables deterministic failure injection.
  Tests (app target): rollback-on-insert/update + flag lifecycle; history
  session-usability-with-signal; recents write-through gating for record/clear.

### HB-026 (Low) — reply-target switch destroys draft — FIXED (H3-05)
- Code: VideoPageView replyTarget set at :550-551 clears composerText unconditionally; submit success
  path :713-735 clears properly.
- Disposition: FIXED in H3-05 — per-target draft store (top-level sentinel +
  reply:<commentID> keys). Switching targets parks the current text under the
  outgoing key and restores the incoming target's parked draft; Cancel parks
  rather than discards; only successful submit consumes the draft.
  onChange(of: replyTarget?.id) uses the iOS 17 two-parameter form.

### HB-027 (Medium) — per-card history scans + formatter churn — FIXED (H3-04)
- Code: RootView.swift:493 and SearchView.swift:62 call VideoCard.resumeFraction(videoID:history:
  library.history) inside row builders; library.history is a computed FULL-TABLE fetch evaluated per
  row per body evaluation; VideoCard.relativePublished constructs RelativeDateTimeFormatter per card
  per render (:110-116).
- Disposition: FIXED in H3-04 — LibraryStore.resumeFractions() computes a
  videoID→fraction map in ONE history fetch, memoized against the mutation
  revision (progress ticks cost at most one fetch per surface per generation);
  RootView Home and SearchView hoist the projection once per body and index it
  O(1) per row — the N-rows⇒N-full-table-scans pattern is gone. The old
  VideoCard.resumeFraction(videoID:history:) helper is removed with its exact
  semantics preserved and pinned by app-target tests (in-progress+duration
  only, clamp bounds, invalidation on write/completion/delete).
  VideoCard.relativePublished now uses a cached MainActor-isolated
  RelativeDateTimeFormatter instead of per-card-per-render construction.

### HB-028 (Low) — continue-watching invisible to VoiceOver on cards — FIXED (H3-05)
- Code: VideoCard progress strip :64-76 decoration-only; comment :30-31 explicitly keeps natural
  children exposed (journey contracts depend on it).
- Disposition: FIXED in H3-05 — thumbnail container exposes an accessibilityValue
  "N% watched" when a resume fraction exists, via children: .contain so the
  natural title/channel children (and the journey label contracts) stay intact.
  Thresholds unified: card strip visibility is now any progress in (0,1),
  matching Library rows' !completed semantics (previously 0.01..0.99 band vs >0).

### HB-029 (Low batch) — multiple UX edges — FIXED (H3-03 persistence/navigation + H3-05 remainder)
- AsyncImage(nil URL) spins forever: FIXED in H3-05 — nil legacy thumbnailURL
  renders the bounded failure glyph directly (AsyncImage never leaves .empty
  for nil URLs); real-URL failures keep their existing glyph branch.
- Playlists load lacks generation token: FIXED in H3-05 — check-and-set
  isLoadingPlaylists guard BEFORE first await coalesces overlapping taps;
  PlaylistDetailView gets its own loadInFlight guard (presentation-only
  isLoading starts true to avoid empty-state flash).
- PlaylistDetailView load-error retry: FIXED in H3-05 — real Try again button
  beside the error text (matches removalError affordance).
- Search submit enabled during flight: FIXED in H3-05 — identical query while
  in flight is dropped before recording/submitting AND the button disables;
  different queries always supersede (store generation guard keeps safety).
- Sign-in re-entry guards + truthful fake-session states: FIXED in H3-05 —
  Home and Settings sign-in buttons disable with "Signing in…" during flight;
  non-Google (fake) sessions show "Sign-in isn't available in this session."
  instead of silent no-op.
- Sub-44pt targets/decorative chevrons/history-row hints: FIXED in H3-05 —
  description More/Less, composer Cancel, and per-comment Reply buttons get
  minHeight 44; both decorative chevrons are accessibilityHidden; history/saved
  rows already carried identifiers+hints (verified).
- Continue-watching thresholds differ: UNIFIED in H3-05 (see HB-028).
- TabView no selection/restoration: FIXED in H3-05 — @SceneStorage-backed
  selection binding with tags on all four tabs.
- Share fallback file:///: FIXED in H3-05 — shareURL built only from valid id
  shapes (Core isValidVideoID); otherwise ShareLink is replaced by a button
  that surfaces a controlled "Can't share this video" alert.

### HB-030 (Low) — residual deterministic-test gaps — PARTIALLY FIXED (H3-01 API portions done; remainder owned by H3-06)
- commentThreads pageToken plumbing through client (playlistItems analog tested): FIXED in H3-01
  (wire-shape test asserting videoId/pageToken params present on continuation,
  absent on first page).
- Out-of-range numeric feed-resume index restart: FIXED in H3-01
  (testOutOfRangeResumeIndexRestartsFromFirstPlaylist pins "9|stale-token" restart).
- OfflineLibraryPolicy negative-size/empty-title/tie cases: open -> H3-03/H3-06.
- Recents custom maxEntries below existing count: open -> H3-06 (verify policy trim path).
- Equal-timestamp tie ordering: open -> H3-03/H3-06.
- Disposition: close in H3-06 alongside regressions from H3-01..05 (table-driven, cheapest layer).

## Cross-cutting execution notes

- One coordinator (this session) owns STATE/WAYPOINTS/campaign/checkpoint edits.
- All persistence changes additive; no destructive resets; old-row tolerance pinned by tests.
- No test weakening: HB-015's existing generic-403 test gets re-authored to the new taxonomy with
  equal-or-stronger assertions; journey-affecting UI changes keep identifier contracts stable.
- CI plane: every code wave pushes to main; Core Tests + iOS CI Gate must be green at final SHA.
