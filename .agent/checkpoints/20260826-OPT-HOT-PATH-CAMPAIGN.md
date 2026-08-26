# Checkpoint — OPT_PERFORMANCE_V1 hot-path optimization campaign (2026-08-26)

Campaign opened by explicit owner directive ("comprehensive repository-wide
optimization campaign"), which AGENTS.md/STATE list as one of the three
legitimate triggers for a new coding campaign after H3-EXIT. Scope:
evidence-backed performance work only, all locked invariants preserved,
no behavior contracts changed.

## Shas

- Starting docs tip / HEAD: `7968a5d` (qualified code baseline was `7a70943`)
- Code commit: `3fbf1d8` — perf: eliminate hot-path full-table scans and
  parallelize feed hydration
- CI/docs commit: `f345958` — ci(perf): DerivedData reuse across runs;
  drop per-run brew update; docs/04 hydration policy; HB-031/HB-032 backlog

## Findings and fixes (root cause -> change)

1. Home feed detail hydration was a serial network waterfall
   (`YouTubeAPI.swift` default `fetchSubscriptionFeed`): every 50-id
   `videos.list` batch waited for the previous one. N-batch first pages paid
   N sequential round trips before render. Fix: bounded sliding-window task
   group (width 4), results placed by batch index, output order identical to
   input order regardless of completion order. Quota cost unchanged (every
   batch is fetched regardless); error contract unchanged (first failure
   fails the page). Playlist walk left strictly sequential ON PURPOSE: its
   pause-point continuation semantics ARE the quota bound (HB-031 records
   why concurrency there is a product decision, not an optimization).
   Tests: FeedScriptedAPI hardened with a lock; batch-append-order pins made
   order-insensitive while strict output ordering stays pinned; NEW regression
   test forces inverted completion order (slow first batch) proving
   deterministic concatenation.

2. LibraryStore point lookups materialized ENTIRE tables then filtered in
   memory (`historyEntryOrThrow`, `savedItemOrThrow`, `downloadedEntryOrThrow`).
   These run on warm paths: recordProgress fires every 5 s during playback;
   resumePosition/isSaved fire on every video-page open. Fix: `#Predicate`
   store-filtered fetches with fetchLimit 1. O(table) materialization ->
   store-level row selection.

3. LibraryView (RootView) fetched the full history table TWICE plus the saved
   table TWICE per body evaluation (`store.history.filter`, `prefix(20)`,
   `store.saved.isEmpty` + `ForEach(store.saved)`). Fix: revision-memoized
   `historySnapshot()` / `savedSnapshot()` in LibraryStore (same pattern as
   the existing `resumeFractions()` projection): at most ONE fetch per table
   per mutation generation, sections filter in memory.

4. DownloadManager metadata lookups were write-only-cache/read-full-scan:
   `metadataCache` existed but `presentationMetadata(taskID:)` never read it,
   and DownloadsView calls it PER RENDERED ROW (active+queued+failed rows),
   re-fetching and linear-scanning the whole records table per visible row on
   EVERY progress-tick invalidation. Same full-table scan pattern in
   `upsertRecord`, `persistQueuedState`, `syncRecord`,
   `setPresentationMetadata`, `clearStaleQueuedRecord`, cancel's queued branch,
   `plannedDurationSeconds`. Records persist forever once a download
   completes, so scans scaled with LIFETIME download history. Fix:
   - presentationMetadata reads the cache first (backfills on miss; unknown
     ids never cached negatively);
   - plannedDurationSeconds memoized (value written once at enqueue);
   - new `recordOrThrow(id:)` predicate row fetch replaces all single-id
     full-table scans;
   - activeLogicalCounts uses in-store `fetchCount` predicates instead of
     materializing every row on each enqueue/promotion attempt;
   - persistedQueuedJobs fetches only `.queued` rows.
5. DownloadRecord allocated JSON coders per access inside projection passes
   (`records` maps every persisted row through downloadTask -> components),
   charging one decoder allocation per lifetime row per enqueue. Fix: shared
   static coders (`nonisolated(unsafe)`, same documented pattern as APIDate).
6. DownloadsView computed offline summaries twice per body evaluation
   (header + content sections), each a full SwiftData index fetch + mapping +
   policy sort/group. Fix: compute once per body, thread through both
   sections. Per-row `presentationMetadata` reads are covered by fix 4.
7. VideoPageView allocated a DateFormatter on every body evaluation
   (`publishedLabel`). Fix: cached @MainActor static formatter (mirrors
   VideoCard's HB-027 fix).
8. ios-ci wasted minutes per run: `brew update` network refresh every run and
   zero build-product caching (GoogleSignIn/YouTubeKit/app recompiled from
   scratch each run). Fix: workspace-local derived-data path whose Build
   products and SourcePackages checkouts are cached via actions/cache keyed
   on project.yml + Package.swift + xcconfig (restore-keys fallback); dropped
   brew update. Gate contract untouched; verify-gate-contract.sh passes.

## Honest measurement statement

The authoring host is Windows (no iOS runtime/Xcode), so wall-clock
device/simulator numbers cannot be produced locally and none are claimed.
Measured/verifiable facts:

- Local Windows matrix green before AND after: swift build clean; swift test
  141 XCTest + 11 swift-testing, 0 failures (~0.3 s test aggregate; suite is
  not the bottleneck).
- Structural complexity changes (code-inspection counts):
  - LibraryView body: history-table fetches 2 -> <=1 per mutation generation
    (plus saved 2 -> <=1).
  - DownloadsView per progress tick: full-table record fetches went from
    ~(1 per visible metadata row) + 2 offline-index fetches to <=1 offline
    index fetch + cache hits; record lookups O(lifetime rows) -> O(matching
    row) store-filtered.
  - Feed cold start hydration latency: ceil(pages/50) serial round trips ->
    approximately ceil(pages/(50*4)) windows' worth of round trips (bounded
    fan-out of 4), i.e. ~4x fewer sequential round trips for multi-batch
    pages; identical request count and quota cost.
  - CI: package resolution + dependency/app compilation reused across runs
    instead of clean rebuilds every run.
- Hosted qualification (real verdicts): Core Tests run 32917219011 SUCCESS
  and iOS CI fail-closed Gate run 32917219009 SUCCESS at code SHA 3fbf1d8
  (Build Debug/Release, 141 XCTest, journeys 20/20). f345958 workflow-edit
  qualification recorded below when observed.

## Invariants preserved

- FocusTubeCore platform-neutral (still no UIKit/SwiftUI/AV*/SwiftData/
  GoogleSignIn/YouTubeKit imports; verified by inspection of touched file).
- No yt-dlp/remote-extractor/FFmpeg/backend; download ladder untouched;
  Shorts/firewall paths untouched; autoplay-next absent.
- Persistence changes are access-pattern only; NO schema/model changes, so no
  migration surface moved.
- Error taxonomy, pagination semantics, duplicate-submit guards, truthful
  persistence flags, accessibility contracts and XCUITest identifiers all
  unchanged; existing tests were strengthened (thread-safe stub), never
  weakened; one new deterministic ordering test added.

## Deferred (recorded in HARDENING_BACKLOG)

- HB-031: concurrent playlist walk (quota-policy redesign needed).
- HB-032: event-driven waitForCompletion (bounded-cost polling; settle
  cluster re-proof risk outweighs gain).

## Durable state

STATE.yaml/WAYPOINTS.yaml updated by this checkpoint commit; repo baseline
pointer refreshed to the final qualified code SHA per the pointer convention
(code-affecting change landed with hosted green runs).
