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
        mediaDirectory: URL = Self.defaultMediaDirectory(),
        incompleteDirectory: URL = Self.defaultIncompleteDirectory()
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
        reconcileOnLaunch()
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

    public func reconcileOnLaunch() {
        // Drop background tasks from a previous process lifetime; they cannot be
        // transparently re-bound, so their records are reconciled to interrupted
        // and made retryable below.
        (transport as? BackgroundDownloadTransport)?.cancelAll()

        let records = fetchRecords()
        let tasks = records.map { $0.downloadTask }
        let reconciled = DownloadReconciler.reconcile(tasks) { [weak self] url in
            self?.fileExists(url) ?? false
        }
        for (record, task) in zip(records, reconciled) {
            if record.statusRaw != task.state.status.rawValue || record.errorRaw != task.state.error?.rawValue {
                record.apply(task)
            }
        }
        try? context.save()
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
        context.insert(DownloadRecord(task: task))
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
}
