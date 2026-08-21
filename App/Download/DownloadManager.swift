import Foundation
import SwiftData
import FocusTubeCore
import AVFoundation

/// App-layer durable download manager. Owns the deterministic `DownloadCoordinator`
/// and persists `DownloadRecord` metadata in SwiftData, reconciles on relaunch,
/// refuses downloads when storage is insufficient, and cleans up on
/// cancel/failure without orphaning final media. Final media is stored under
/// Application Support (never the temporary directory); transient component
/// files use a durable incomplete-work area there.
@MainActor
@Observable
public final class DownloadManager {
    public private(set) var liveTasks: [DownloadTask] = []

    /// Invoked on the main actor when a download reaches `.completed` through
    /// the reattached-background path. RootView wires this to library
    /// registration so offline media finished outside the app is not orphaned.
    public var onMediaFinalized: (@MainActor (DownloadTask) -> Void)?

    private let coordinator: DownloadCoordinator
    private let context: ModelContext
    private let storage: StorageProviding
    private let mediaDirectory: URL
    private let incompleteDirectory: URL
    private let transport: DownloadTransport

    public init(
        transport: DownloadTransport,
        context: ModelContext,
        storage: StorageProviding = VolumeStorage(),
        mediaDirectory: URL = DownloadManager.defaultMediaDirectory(),
        incompleteDirectory: URL = DownloadManager.defaultIncompleteDirectory()
    ) {
        self.context = context
        self.storage = storage
        self.mediaDirectory = mediaDirectory
        self.incompleteDirectory = incompleteDirectory
        self.transport = transport
        self.coordinator = DownloadCoordinator(
            transport: transport,
            directory: incompleteDirectory,
            mux: Self.makeMux()
        )
        // Reconciliation awaits transport reattachment, so it runs as a task;
        // `reconcileOnLaunch()` is idempotent and may also be awaited directly.
        Task { await reconcileOnLaunch() }
    }

    // MARK: - Durable paths

    public static func defaultMediaDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FocusTube").appendingPathComponent("Media")
    }

    public static func defaultIncompleteDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("FocusTube").appendingPathComponent("Incomplete")
    }

    /// Native AVFoundation mux of adaptive video+audio components into the final
    /// file. Defined here (App layer) so Core stays free of AVFoundation; the
    /// coordinator invokes it through the injected closure.
    private static func makeMux() -> (@Sendable ([URL], URL) async throws -> URL) {
        { components, destination in
            let muxer = await AdaptiveMuxer()
            guard components.count == 2 else { throw MuxError.missingComponent }
            let result = await muxer.mux(
                videoURL: components[0],
                audioURL: components[1],
                outputURL: destination
            )
            switch result {
            case .success(let url): return url
            case .failure(let error): throw error
            }
        }
    }

    // MARK: - Reconciliation

    /// Reattaches to background transfers that survived the previous process
    /// lifetime and resumes driving them through the coordinator state machine;
    /// every other persisted record is reconciled with filesystem reality, so
    /// in-flight work whose tasks did not come back becomes interrupted and
    /// retryable. Idempotent: reattachment and reconciliation are no-ops for
    /// already-attached tasks and settled records.
    public func reconcileOnLaunch() async {
        let recovered = await transport.reattach { [weak self] requestID, event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.coordinator.handle(event, taskID: requestID)
                await self.persistTaskSnapshot(requestID)
            }
        }
        let recoveredByID = Dictionary(recovered.map { ($0.requestID, $0) }, uniquingKeysWith: { first, _ in first })

        let records = fetchRecords()
        let tasks = records.map { $0.downloadTask }
        let reconciled = DownloadReconciler.reconcile(tasks) { [weak self] url in
            self?.fileExists(url) ?? false
        }
        for (record, task) in zip(records, reconciled) {
            // Fully recovered transfers keep running; everything else settles
            // to filesystem-backed reality — including partially recovered
            // jobs, whose surviving siblings can never produce a final file.
            if let info = recoveredByID[record.id],
               !info.isPartialRecovery(componentCount: record.components.count) {
                continue
            }
            if record.statusRaw != task.state.status.rawValue || record.errorRaw != task.state.error?.rawValue {
                record.apply(task)
            }
        }
        try? context.save()

        for record in records {
            guard let info = recoveredByID[record.id] else { continue }
            if info.isPartialRecovery(componentCount: record.components.count) {
                // Some components died with the previous process, so the job
                // can never finalize. Cancel the surviving transfers so the
                // background session drains instead of feeding a doomed job.
                await transport.cancel(taskID: record.id)
            } else {
                let request = DownloadRequest(
                    id: record.id,
                    videoID: record.videoID,
                    resolution: record.resolution,
                    destinationURL: record.destinationURL,
                    components: record.components
                )
                await coordinator.attach(taskID: request.id, request: request)
            }
        }
        // A recovered transfer without a persisted record would stream orphaned
        // bytes forever; cancel it so the background session drains.
        let recordedIDs = Set(records.map(\.id))
        for requestID in recoveredByID.keys where !recordedIDs.contains(requestID) {
            await transport.cancel(taskID: requestID)
        }
    }

    // MARK: - Control

    @discardableResult
    public func enqueue(_ request: DownloadRequest, requiredBytes: Int64 = 0) async -> DownloadTask {
        if requiredBytes > 0 && requiredBytes > storage.availableCapacity(for: request.destinationURL) {
            var task = DownloadTask(
                id: request.id,
                videoID: request.videoID,
                resolution: request.resolution,
                destinationURL: request.destinationURL,
                components: request.components,
                state: DownloadState(status: .failed, error: .storageRefused)
            )
            context.insert(DownloadRecord(task: task))
            try? context.save()
            return task
        }

        let task = await coordinator.enqueue(request)
        // Upsert: retries/re-resolutions reuse the same request id, and
        // duplicate SwiftData records would corrupt reconciliation.
        if let existing = fetchRecords().first(where: { $0.id == request.id }) {
            existing.apply(task)
        } else {
            context.insert(DownloadRecord(task: task))
        }
        try? context.save()
        return task
    }

    public func begin(_ taskID: String) async {
        await coordinator.begin(taskID) { [weak self] task in
            Task { @MainActor in
                self?.applyLive(task)
            }
        }
        await syncRecord(taskID)
    }

    public func cancel(_ taskID: String) async {
        await coordinator.cancel(taskID)
        await syncRecord(taskID)
        removeLive(taskID)
    }

    public func retry(_ taskID: String) async {
        guard let record = fetchRecords().first(where: { $0.id == taskID }) else { return }
        let components = record.components
        guard !components.isEmpty else { return }
        let request = DownloadRequest(
            id: record.id,
            videoID: record.videoID,
            resolution: record.resolution,
            destinationURL: record.destinationURL,
            components: components
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin(request.id) { [weak self] task in
            Task { @MainActor in
                self?.applyLive(task)
            }
        }
        await syncRecord(taskID)
    }

    public var records: [DownloadTask] {
        fetchRecords().map { $0.downloadTask }
    }

    public var activeTasks: [DownloadTask] {
        records.filter { status in
            switch status.state.status {
            case .queued, .downloading, .paused, .validating, .muxing, .finalizing, .waitingForRetry, .resolving, .reResolving:
                return true
            default:
                return false
            }
        }
    }

    /// Snapshot of a task currently held by the coordinator, for diagnostics
    /// and tests (e.g. verifying a reattached background task is driving again).
    public func coordinatorTask(_ id: String) async -> DownloadTask? {
        await coordinator.task(id)
    }

    /// Blocks until the coordinator reports the task completed or failed, or the
    /// timeout elapses. Used by `DownloadService` to register finalized media.
    public func waitForCompletion(_ id: String, timeout: TimeInterval = 600) async -> DownloadTask? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let task = await coordinator.task(id),
               task.state.status == .completed || task.state.status == .failed {
                await syncRecord(id)
                return task
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return await coordinator.task(id)
    }

    // MARK: - Live progress (UI projection)

    private func applyLive(_ task: DownloadTask) {
        if let idx = liveTasks.firstIndex(where: { $0.id == task.id }) {
            liveTasks[idx] = task
        } else {
            liveTasks.append(task)
        }
        if task.state.status == .completed || task.state.status == .failed {
            removeLive(task.id)
        }
    }

    private func removeLive(_ taskID: String) {
        liveTasks.removeAll { $0.id == taskID }
    }

    // MARK: - Helpers

    private func fetchRecords() -> [DownloadRecord] {
        (try? context.fetch(FetchDescriptor<DownloadRecord>())) ?? []
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func syncRecord(_ taskID: String) async {
        guard let record = fetchRecords().first(where: { $0.id == taskID }) else { return }
        guard let task = await coordinator.task(taskID) else { return }
        record.apply(task)
        try? context.save()
    }

    /// Projects a coordinator event's resulting task into the UI and persists
    /// it. Used by reattached background transfers, whose events bypass
    /// `begin(_:)`.
    private func persistTaskSnapshot(_ taskID: String) async {
        guard let task = await coordinator.task(taskID) else { return }
        applyLive(task)
        await syncRecord(taskID)
        // A transfer that finishes via the relaunched background session never
        // passes through DownloadService, so register it here; the library
        // upserts by id so in-app registration stays idempotent.
        if task.state.status == .completed {
            onMediaFinalized?(task)
        }
    }
}
