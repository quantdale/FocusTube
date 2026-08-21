# Hardening Backlog — Deferred During Implementation Campaign

This file is the parking lot for nonblocking Medium/Low quality work discovered while implementing M0–M8. It exists to prevent autonomous agents from spending the implementation campaign polishing indefinitely.

## Rules

- Critical/High correctness, data-integrity, security, secret-leak, build, or no-Shorts regressions are **not** deferred; fix them immediately.
- Medium/Low debt that does not block the active acceptance gate is logged here and implementation continues.
- Do not start a broad hardening sweep during `IMPLEMENTATION_V1` unless the user/state explicitly changes campaign.
- Each item should be specific enough for a later hardening agent to reproduce or inspect.

## Item template

```markdown
### HB-xxx — short title
- Severity: Medium | Low
- Discovered in: WP-xxx / commit
- Area: subsystem/files
- Evidence/reproduction: ...
- Impact: ...
- Suggested hardening action: ...
- Blocks implementation: no
```

## Backlog

### HB-001 — VideoPageView registers onProgress after loadAndPlay
- Severity: Low
- Discovered in: INTEGRATION_COMPLETION_V1 audit (cba7e67 era)
- Area: App/Video/VideoPageView.swift
- Evidence/reproduction: `coordinator.onProgress = ...` is assigned after `await coordinator.loadAndPlay(...)` returns; progress callbacks fired during early playback setup are missed.
- Impact: first moments of playback progress may not render.
- Suggested hardening action: register the callback before calling loadAndPlay.
- Blocks implementation: no
- Resolved 2026-08-21: VideoPageView registers onProgress and Now Playing metadata before loadAndPlay.

### HB-002 — reattached downloads restart progress aggregation at zero
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/BackgroundDownloadTransport.swift, App/Download/DownloadManager.swift
- Evidence/reproduction: after relaunch reattachment, byte counts are not seeded from the persisted record; UI progress restarts from 0 until the next cumulative didWriteData event.
- Impact: cosmetic progress regression after relaunch; correctness unaffected (URLSession totals are cumulative).
- Suggested hardening action: seed componentProgress from the persisted record on attach.
- Blocks implementation: no

### HB-003 — tiny event window between reattach registration and coordinator attach
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/DownloadManager.swift reconcileOnLaunch
- Evidence/reproduction: a .completed delegate event landing between transport handler registration and coordinator.attach is dropped; that transfer would sit .downloading until next retry.
- Impact: rare stuck record after a precisely-timed relaunch.
- Suggested hardening action: buffer early events in the transport or re-check task states after attach.
- Blocks implementation: no

### HB-004 — stale-response race in SearchStore/HomeFeedStore loads
- Severity: Medium
- Discovered in: HARDENING_V1 audit (dd5d648 era)
- Area: App/Search/SearchStore.swift, App/Home/HomeFeedStore.swift
- Evidence/reproduction: concurrent submit/load calls are not serialized; last response wins and can regress visible state.
- Impact: observable state may briefly show older results.
- Suggested hardening action: generation token or task cancellation per load.
- Blocks implementation: no

### HB-005 — Now Playing metadata never published
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Media/BackgroundMediaCoordinator.swift (updateNowPlaying has no call sites)
- Impact: lock screen shows no title/artwork/duration though remote commands work.
- Suggested hardening action: publish via NowPlayingInfoBuilder on playback state changes/progress ticks.
- Blocks implementation: no
- Resolved 2026-08-21: PlayerCoordinator exposes nowPlayingSnapshot + onNowPlayingChanged (item change, state transitions, 5s progress ticks); BackgroundMediaCoordinator.publishNowPlaying writes/clears MPNowPlayingInfoCenter; wired in RootView.

### HB-006 — per-event unstructured Tasks allow event reordering
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Sources/FocusTubeCore/Download/DownloadCoordinator.swift begin(onEvent:), App/Download/DownloadManager.swift reattach handler
- Impact: a late progress/completed Task can overtake a failed event; benign today because transitions guard, but ordering is not guaranteed.
- Suggested hardening action: serialize events per task (AsyncStream mailbox).
- Blocks implementation: no

### HB-007 — RootView.init side effects run on every struct evaluation
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/RootView.swift init, App/Download/DownloadManager.swift init-spawned reconcile Task
- Impact: discarded instances still open containers/spawn reconciliation.
- Suggested hardening action: hoist dependencies into a single container created in FocusTubeApp.
- Blocks implementation: no

### HB-008 — waitForCompletion polls up to 10 min and ignores cancellation
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Download/DownloadManager.swift waitForCompletion
- Impact: dismissed views keep polling; timeout reports failure while transfer continues (late completion then registers media — user saw a false failure).
- Suggested hardening action: checkCancellation per iteration + event-driven continuation; distinguish timed-out-but-active from settled failure.
- Blocks implementation: no
- Resolved 2026-08-21: waitForCompletion throws CancellationError on task cancellation and returns the still-active task on timeout; DownloadService treats active-on-timeout as non-failure (transfer continues, record settles via events).

### HB-009 — storage admission floor never enforced
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Download/DownloadService.swift (requiredBytes always 0), docs/03 storage rule
- Impact: full device drives cryptic finalization/mux failures instead of typed storageRefused.
- Suggested hardening action: enforce free-space floor before begin, or expose stream byte sizes for real estimates.
- Blocks implementation: no
- Resolved 2026-08-21: StorageEstimator (Core) computes conservative requiredBytes from duration+tier with adaptive headroom; DownloadService passes it to enqueue so storageRefused precedes any partial work.

### HB-010 — final validation is existence+size only
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Sources/FocusTubeCore/Download/DownloadCoordinator.swift finalize
- Impact: truncated-but-nonempty files register as completed.
- Suggested hardening action: injected AVFoundation asset-validator seam at app layer.
- Blocks implementation: no
- Resolved 2026-08-21: DownloadCoordinator accepts an injected validate seam run on the finalized file; the app supplies AVFoundation track validation (MediaAssetValidator) and failing files are discarded as .validationFailed.

### HB-011 — test gaps: malformed payloads per endpoint, store error paths, comments-disabled detection
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Tests/FocusTubeCoreTests, FocusTubeTests
- Suggested hardening action: table-driven malformed-JSON cases per endpoint; SearchStore/HomeFeedStore deterministic error tests incl. 401; commentsDisabled 403-envelope fixture.
- Blocks implementation: no

### HB-012 — Low batch
- Severity: Low
- Items: transport-held closures retain coordinator until terminal event; removeTarget(nil) blast radius; PlayerCoordinator deinit teardown assumption; in-memory fallback try!; duplicate extraction per video page + unordered history writes; muxing-* orphan sweep at launch; DownloadRecord components decode-failure silent no-op retry; try? context.save() silent failures; VolumeStorage 0-on-error ambiguity; empty Media/<id>/<quality>/ dirs never pruned; layout divergence Media/<videoID>/<quality>/ vs spec Media/<videoID>/media.<container> (multi-quality justification noted, ADR line pending).
- Blocks implementation: no