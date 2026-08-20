# Checkpoint 2026-08-20 — Reaudit + PHASE A integration fixes

## Context

Independent reaudit of `d3b2454` ("unfinished") rejected the prior
`implementation_complete_ready_for_hardening` claim. Source code + observed CI
win over durable state. The following real defects were confirmed and are being
repaired under `INTEGRATION_COMPLETION_V1`.

## Defects repaired (this checkpoint)

### A. PlayerCoordinator structural compile regression

`playLocalFile()` closed the class body prematurely; `stop()`, progress
observers, and status handlers were outside the class. Fixed by rewriting the
class with correct brace structure and a single coherent body.

### B. DownloadManager async correctness

`DownloadManager.syncRecord` was a non-`async` method that `await`ed
`coordinator.task(...)`. Made `syncRecord` `async` and `await`ed at call sites.
Also removed an actor-isolated `coordinator.transport` access from
`reconcileOnLaunch` (would require `await` across the actor boundary) by storing
the `transport` reference directly on `DownloadManager`.

### C. Fake background download replaced

`URLSessionDownloadTransport` (foreground `.shared`, no-op `cancel`) deleted and
replaced by `BackgroundDownloadTransport`: real
`URLSessionConfiguration.background(withIdentifier:)`, stable session identifier,
`URLSessionDownloadDelegate` bridge, per-component task tracking keyed by
`taskIdentifier`, progress/completed/failed event delivery, real `cancel`, and
`cancelAll()` for relaunch hygiene. A shared singleton exists before `RootView`
so relaunch/background completions reach the delegate; `FocusTubeAppDelegate`
forwards the system background completion handler.

### D. Exact-quality download orchestration

Added `DownloadPlanner` (Core, deterministic): exact combined → direct download;
else exact video-only + audio-only → adaptive mux; else `unavailable` (never
silent downgrade). `DownloadService` now uses the planner and drives the
component-aware `DownloadCoordinator`. `DownloadQualityPicker` shows only
qualities the planner can actually satisfy.

### E. Permanent media storage

`DownloadManager` default `directory` is now Application Support
(`FocusTube/Media/<videoID>/<quality>/media.mp4` final; `FocusTube/Incomplete`
for transient components) instead of `NSTemporaryDirectory`. `DownloadRecord`
persists components so interrupted downloads are retryable after relaunch.

### F. Real end-to-end wiring + progress UI

`RootView` wires the real transport, `DownloadManager`, `DownloadService`, and a
Downloads tab that shows live download progress (`liveTasks`) plus completed
library items with offline playback and deletion. Background media + remote
commands remain wired.

## Status

- PHASE A (compile correctness) and PHASE C (real background download + adaptive
  integration) implemented in code.
- CI (ios-ci + core) pending observation after push.
- Not yet validated on Apple build plane.

## Next

Push and observe `ios-ci` + `core` runs; fix any Swift 6 compile errors surfaced
by CI; then proceed to PHASE B/E/F/G integration validation and HARDENING_V1.
