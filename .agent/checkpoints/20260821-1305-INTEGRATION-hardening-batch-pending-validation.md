# Checkpoint — INTEGRATION_COMPLETION_V1: hardening implementation batch (validation pending)

- Date: 2026-08-21 (~13:05 local)
- Branch: main
- HEAD at write time: f609cd3 (8 commits ahead of last-pushed d5881c5-era work; nothing pushed since f3db8e9)
- Status: partial — implementation complete, validation intentionally deferred by owner instruction ("only do code implementation, do not do any testing yet")

## What happened

Owner paused all test/CI activity. In that window the entire remaining Medium
hardening backlog plus most of the Low batch was implemented and committed
locally, one coherent commit per slice:

| Commit | Backlog | Content |
|---|---|---|
| a9c8c70 | HB-001/005/008/009/010 | Now Playing publishing (snapshot + onNowPlayingChanged + MPNowPlayingInfoCenter wiring), progress/metadata callbacks registered before loadAndPlay, cancellation-aware waitForCompletion with active-on-timeout no-failure, StorageEstimator admission before enqueue, injected validate seam in DownloadCoordinator + AVFoundation MediaAssetValidator |
| 0f05f0a | HB-004 | loadGeneration tokens in SearchStore/HomeFeedStore; superseded responses cannot mutate state; isLoading owned by newest load |
| e12d1ce | HB-002/003 | reattach event buffer routed per-request during reconcileOnLaunch; coordinator.seedProgress seeds cumulative bytes from persisted record |
| e3bea1a | HB-007 | AppDependencies (@MainActor) owns container/stores/coordinator creation; FocusTubeApp holds it in @State; RootView consumes it |
| d69d966 | HB-006 | DownloadCoordinator.handle chains events per taskID for strict arrival-order application; onUpdate fires from serialized path |
| 0a9584b | HB-012 + ADR | sweepMuxingOrphans at launch; ADR-0006 accepted (per-quality media layout authoritative) |
| 20ec84f | HB-012 | context.save() failures logged (LibraryStore/DownloadManager); VolumeStorage logs failed capacity queries and refuses conservatively; empty <quality>/<videoID> dirs pruned on delete/reconcile |
| f609cd3 | HB-012 | quality picker reuses PlayerCoordinator.lastResolvedMedia (no duplicate extraction per page) |

Backlog disposition after this batch: every item implemented or explicitly
dispositioned in `.agent/HARDENING_BACKLOG.md` (remaining sub-items are no-op
by analysis or documented tradeoffs).

## Evidence status

- Validated (observed earlier, still standing):
  - Core Tests green on Apple CI through f3db8e9 (run 32479222209).
  - ios-ci on f3db8e9: steps 1–10 green — **app-hosted unit tests passed in
    52s** (run 32479222149, job 96761959878, step "Unit tests (FocusTubeTests)"
    11:59:19→12:00:11Z). The historical 55-minute hang is therefore narrowed to
    the UI-test leg / combined-session behavior; UI step was in progress when
    observation stopped.
- NOT validated (pending): all 8 commits above. No swift test run, no push, no
  CI observation since the owner's instruction. New Core APIs (seedProgress,
  validate seam, StorageEstimator) have deterministic coverage to be added/run
  during validation.

## Exact next actions for a fresh agent

1. Run local `swift test` (Windows toolchain path in session notes / START_HERE).
2. Add/adjust deterministic tests for new Core surface if desired:
   StorageEstimator.requiredBytes tiers+adaptive headroom+unknown-duration-0;
   DownloadCoordinator.seedProgress; validate-seam failure → .validationFailed
   with file discarded.
3. Push a9c8c70..f609cd3 to main; observe ios-ci + Core Tests.
4. If UI-test leg hangs again, read watchdog annotations (unit-progress/
   ui-progress warnings) from the check-run; LaunchTests/app-launch is the
   prime suspect.
5. On green: flip G0 boxes 3/5/6 + IC-EXIT in docs/14-ACCEPTANCE-GATES.md,
   sync STATE.yaml/WAYPOINTS.yaml (WP-003/004/005 statuses), README status
   line, then final report + terminal state personal_release_candidate.
