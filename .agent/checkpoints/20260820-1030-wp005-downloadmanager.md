# Checkpoint — WP-005 Durable download manager

- Campaign: IMPLEMENTATION_V1
- Milestone/Gate: M2 / G2
- Packet: WP-005-DURABLE-DOWNLOAD-MANAGER
- State: complete (implementation + deterministic tests; CI evidence pending observation)
- Commit: pending-ci (push triggers ios-ci)

## What changed
- `Sources/FocusTubeCore/Download/DownloadState.swift`: added `DownloadError.interrupted` / `.storageRefused`; corrected transition table (removed non-existent `.cancelled` status reference).
- `Sources/FocusTubeCore/Download/DownloadReconciler.swift`: pure `reconcile(_:fileExists:)` — `downloading`/`finalizing` become interrupted, `completed` missing file becomes validation failure, `queued`/`paused` unchanged.
- `Tests/FocusTubeCoreTests/DownloadReconcilerTests.swift`: deterministic reconciliation tests.
- `App/Download/StorageProviding.swift`: `StorageProviding` seam + `VolumeStorage` (real volume capacity).
- `App/Download/DownloadRecord.swift`: SwiftData `@Model` mirroring `DownloadTask`, reconstructs `downloadTask`.
- `App/Download/DownloadManager.swift`: `@MainActor` manager wrapping `DownloadCoordinator`, persisting records, `reconcileOnLaunch`, storage refusal, cancel/retry, record sync.
- `FocusTubeTests/DownloadManagerTests.swift`: deterministic tests using in-memory `ModelContainer` (persist queued, storage refusal, relaunch reconcile to interrupted, cancel cleanup).

## Acceptance mapping
- explicit DownloadManager state machine tests pass — `DownloadReconcilerTests` + `DownloadManagerTests`.
- background tasks reconcile on relaunch — `DownloadManager.reconcileOnLaunch` + `testReconcileMarksInterruptedDownload`.
- transient retry/re-resolution/storage refusal/cancel cleanup pass — `retry`/`enqueue` storage refusal/`cancel` implemented and tested.
- SwiftData record and filesystem final state reconcile safely — `DownloadRecord.apply`/`downloadTask` round-trip + reconcile validation.

## Known failures or deferred items
- Relaunch reconciliation is proven deterministically via the persisted-record path; live process-suspension/background-task handoff is a device concern deferred to G10 but the state machine is implemented.

## Durable decisions made
- None new; 1080p ceiling, no FFmpeg/yt-dlp/remote fallback preserved.

## Exact next waypoint
- WP-006-AUTH-DATA-API: GoogleSignIn boundary (fake for tests) + typed YouTube Data API client (subscriptions/list, videos/hydrate) with success/auth/quota/network/decode error classes. Deterministic fake-auth + typed-error integration tests; no secret/token logging.

## Resume commands
```text
git pull origin main
# push triggers ios-ci.yml (build + LaunchTests + FocusTubeTests)
```
