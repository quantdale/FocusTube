# SPEC_CLOSURE_DAILY_DRIVER_V2 — Checkpoint 1

Date: 2026-08-24
Campaign: `SPEC_CLOSURE_DAILY_DRIVER_V2` (opened by owner directive)
Base at open: `934dc69` (docs tip; code baseline 42f761a)

## What this checkpoint covers

Packets DDV2-00 through DDV2-08 (Core + App implementation waves), landed as a
series of coherent commits on `main`. Statuses below are provisional pending
the iOS CI run covering each wave; final evidence recorded at DDV2-EXIT.

## Truth reset findings (DDV2-00)

| Claim under audit | Finding |
|---|---|
| Durable queued-download recovery | CONFIRMED DEFECT — fixed this campaign (see below) |
| Comment/reply posting exists | CONFIRMED ABSENT pre-campaign — implemented (DDV2-03) |
| Subscribe/unsubscribe/rating UI exposure | Was service-only; now real UI with server-backed state (DDV2-04) |
| Account/settings surface | Did not exist — implemented (DDV2-05) |
| Home cards thumbnail/duration/publish | Were text rows — rebuilt with VideoCard (DDV2-06) |
| Search recent-query suggestions | Absent — implemented locally, no per-keystroke network (DDV2-07) |
| Library playlists/storage management | Playlists absent — bounded subset added; storage summary + sorting added to Downloads (DDV2-02/08) |
| STATE "no open debt" vs HB-013/HB-014 | Contradiction acknowledged in STATE.yaml; both closed this campaign |

## P0 durable queued-download repair (DDV2-01)

Defect: capacity-deferred downloads were persisted `.queued` while promotion
state lived only in `DownloadService.pendingRequests` process memory. After
relaunch: no promotion path AND `.queued` counted toward
`activeLogicalCount` → two stranded rows could permanently deadlock all
download admission.

Architecture fix:
- `DownloadRecord.queuedMetadataData` additive payload (`QueuedDownloadMetadata`)
  persists planning metadata; queued rows persist NO signed URLs.
- `.queued` records no longer occupy active slots; strict FIFO precedence via
  `DownloadQueuePolicy` (new Core type); promoted heads bypass only sibling
  precedence, never the budget (`exceedsBudget`).
- `DownloadService.restorePersistedQueue()` reconstructs the queue after launch
  reconciliation (FIFO by record createdAt); promotion drains immediately when
  budget allows; `onTaskSettled` covers reattached/cancel settlements from a
  previous process lifetime.
- Queued cancel deletes the record outright; corrupt/legacy rows degrade to
  typed `queueStateCorrupted` failure (actionable, slot-free); legacy rows
  synthesize payloads from their own fields and promote normally.

## Other waves

- DDV2-02: retry policy reconciled to docs/03 (three attempts total, structurally
  bounded loop); DownloadsView rebuilt (phases copy, % + sizes, durable queue
  section, offline sorting by newest/largest/channel, total storage usage,
  human-readable sizes); pause/resume honestly documented as unsupported.
- DDV2-03: typed commentThreads.insert / comments.insert, subscription lookup
  (`forChannelId`) carrying the resource id needed for truthful unsubscribe,
  getRating state model, input validation before network, `.invalidInput` case.
- DDV2-04: video page action row (save/like/subscribe/share), optimistic like +
  subscribe with explicit rollback, authoritative initial states, comment
  composer with duplicate-submit prevention and tree updates, typed account
  error alert; VideoSummary gained additive `channelID`.
- DDV2-05: AccountSettingsView (auth state/sign-in/out preserving local data,
  principles, download policy incl. no-pause honesty, storage summary, privacy,
  version) reachable from Home toolbar profile control (not a fifth tab).
- DDV2-06: shared VideoCard (AsyncImage native loading w/ graceful failure,
  duration badge, relative publish date, local continue-watching strip,
  accessibility labels) used by Home and Search results.
- DDV2-07: RecentSearchStore (SwiftData additive entity) + pure policy
  (dedupe case-insensitive, bound 10, suggestions substring) wired into
  SearchView; recording only on explicit submit; clear/remove controls.
- DDV2-08: additive SwiftData presentation metadata on history/saves
  (publishedAt/thumbnailURL/durationSeconds) with graceful legacy nil;
  continue-watching progress bars; watch-history section; bounded playlists
  surface (list mine → items → play; swipe delete item).
- HB-013: manager projections (`queuedTasks`, `failedTasks`, memoized
  presentation-metadata cache) replace per-render full fetches.
- HB-014: `FixtureMediaFactory` generates a genuinely playable H.264 MP4 at
  runtime for the DEBUG fixture harness; ScriptedDownloadTransport finalizes
  real playable media so journeys can assert true playing state.

## Local validation (observed)

- Windows Swift 6.3.3: `swift build` clean; `swift test` green
  (113 XCTest + 11 swift-testing at last local run, 0 failures).

## Pending at time of writing

- iOS CI runs validating each App-layer wave (Build Debug/Release, unit tests,
  UI journeys, Gate). Final run IDs recorded at DDV2-EXIT or next checkpoint.

## Invariants re-verified

No Shorts surfaces/routes/swipe; filtering before render unchanged; ladder
1080/720/480/360 untouched; Core stays platform-neutral (new Core files import
Foundation only); all API access behind YouTubeAPI protocol; no tokens logged;
SwiftData changes additive only.
