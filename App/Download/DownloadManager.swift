import Foundation
import SwiftData
import FocusTubeCore

/// App-layer durable download manager. Owns the deterministic `DownloadCoordinator`
/// and persists `DownloadRecord` metadata in SwiftData, reconciles on relaunch,
/// refuses downloads when storage is insufficient, and cleans up on
/// cancel/failure without orphaning final media.
@MainActor
public final class DownloadManager {
    private let coordinator: DownloadCoordinator
    private let context: ModelContext
    private let storage: StorageProviding
    private let directory: URL

    public init(
        transport: DownloadTransport,
        context: ModelContext,
        storage: StorageProviding = VolumeStorage(),
        directory: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FocusTubeDownloads")
    ) {
        self.coordinator = DownloadCoordinator(transport: transport, directory: directory)
        self.context = context
        self.storage = storage
        self.directory = directory
        reconcileOnLaunch()
    }

    // MARK: - Reconciliation

    public func reconcileOnLaunch() {
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
                streamID: request.streamID,
                resolution: request.resolution,
                sourceURL: request.sourceURL,
                destinationURL: request.destinationURL,
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
        await coordinator.begin(taskID)
        syncRecord(taskID)
    }

    public func cancel(_ taskID: String) async {
        await coordinator.cancel(taskID)
        syncRecord(taskID)
    }

    public func retry(_ taskID: String) async {
        guard let task = await coordinator.task(taskID) else { return }
        let request = DownloadRequest(
            id: task.id,
            videoID: task.videoID,
            streamID: task.streamID,
            resolution: task.resolution,
            sourceURL: task.sourceURL,
            destinationURL: task.destinationURL
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin(task.id)
        syncRecord(taskID)
    }

    public var records: [DownloadTask] {
        fetchRecords().map { $0.downloadTask }
    }

    // MARK: - Helpers

    private func fetchRecords() -> [DownloadRecord] {
        (try? context.fetch(FetchDescriptor<DownloadRecord>())) ?? []
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func syncRecord(_ taskID: String) {
        guard let record = fetchRecords().first(where: { $0.id == taskID }) else { return }
        guard let task = await coordinator.task(taskID) else { return }
        record.apply(task)
        try? context.save()
    }
}
