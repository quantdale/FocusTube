# Checkpoint — HARDENING_V1 executed; awaiting ios-ci verdict

- Campaign: INTEGRATION_COMPLETION_V1 -> HARDENING_V1
- Milestone/Gate: M9_HARDENING / G9 (in progress)
- Packet: WP-012-HARDEN-RELEASE
- State: partial
- Commit: 2634bf1

## What changed
- HARDENING_V1 audit (3 read-only swarms) produced a prioritized defect list;
  all Critical and High findings fixed across two batches:
  - 20fdedc: CRITICAL URLSession temp-file deletion race (components now move
    synchronously into Application Support/FocusTube/Incomplete staging);
    per-task cancel tracking; coordinator temp cleanup on fail/cancel;
    addDownloadedMedia upsert; late-completion library registration via
    DownloadManager.onMediaFinalized; post-ready buffering no longer
    misreported as stalled.
  - dd5d648: component-index fidelity across relaunch (identity encoded in
    taskDescription); atomic adaptive mux (staging output + validated move);
    search zero-hit guard; <=50-id detail chunking; feed pagination end to end
    with bounded per-channel pages and opaque continuation token; Home
    load-more appends; duplicate-download guard; quality-keyed retry;
    cancel(videoID:quality:) + DownloadsView stop button; comments error row;
    AVAudioSession interruption notifications observed idempotently.
  - 1188870: DownloadService access level (public init exposed internal
    LibraryStore).
- Remaining Medium/Low debt catalogued as HB-004..HB-012 in
  .agent/HARDENING_BACKLOG.md (stale-response races, Now Playing publish,
  event ordering, RootView init side effects, waitForCompletion cancellation,
  storage floor, deep validation seam, extra test matrices, low batch).
- PERSONAL_RELEASE_CHECKLIST.md added (owner-only steps).

## Acceptance evidence
- Local Windows Swift 6.3.3: 63 XCTest + 5 swift-testing, 0 failures.
- Core Tests green on Apple CI at be45a41, ce9f4cd, 9221c4d, cba7e67,
  794be7c, 1460697, 3aef233 (observed via API).
- iOS CI annotations channel now readable anonymously (::error:: lines);
  used to fix LibraryStore/DownloadManager/Bridge/DownloadService errors.
- ios-ci verdict for 1188870 pending at authoring time.

## Known failures or deferred items
- HB-004..012 (Medium/Low) deferred with rationale.
- Live YouTubeKit smokes and real-Google flows remain unexercised (no live
  credentials on CI); deterministic fakes cover the logic.

## Durable decisions made
- none requiring ADRs; multi-quality destination layout divergence from
  docs/03 noted in backlog (HB-012) pending an ADR line.

## Exact next waypoint
- On ios-ci green: mark gates G0-G8 evidence in docs/14, set packets/milestones
  truthful, final report, terminal state personal_release_candidate (or
  implementation_complete_external_validation_required if red persists).
