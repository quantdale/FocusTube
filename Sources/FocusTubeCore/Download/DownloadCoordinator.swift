import Foundation

/// Owns the explicit download state machine, finalization, and validation for
/// all download jobs. Network and filesystem behavior are injected via
/// `DownloadTransport` / `FileManaging` seams so the policy is deterministically
/// testable without real transfers.
public actor DownloadCoordinator {
    private var tasks: [String: DownloadTask]
    private let transport: DownloadTransport
    private let fileManager: FileManaging
    private let directory: URL

    public init(
        transport: DownloadTransport,
        fileManager: FileManaging = FileManager.default,
        directory: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FocusTubeDownloads")
    ) {
        self.transport = transport
        self.fileManager = fileManager
        self.directory = directory
        self.tasks = [:]
    }

    public var allTasks: [DownloadTask] {
        Array(tasks.values)
    }

    public func task(_ id: String) -> DownloadTask? {
        tasks[id]
    }

    // MARK: - Enqueue / control

    @discardableResult
    public func enqueue(_ request: DownloadRequest) -> DownloadTask {
        var task = DownloadTask(
            id: request.id,
            videoID: request.videoID,
            streamID: request.streamID,
            resolution: request.resolution,
            sourceURL: request.sourceURL,
            destinationURL: request.destinationURL
        )
        task.apply(DownloadState(status: .queued))
        tasks[request.id] = task
        return task
    }

    public func begin(_ taskID: String) async {
        guard let task = tasks[taskID], task.state.status == .queued else { return }
        var updated = task
        do {
            try updated.state.transition(to: .downloading)
        } catch {
            return
        }
        tasks[taskID] = updated

        let request = DownloadRequest(
            id: task.id,
            videoID: task.videoID,
            streamID: task.streamID,
            resolution: task.resolution,
            sourceURL: task.sourceURL,
            destinationURL: task.destinationURL
        )
        await transport.begin(request) { [weak self] event in
            Task { await self?.handle(event, taskID: taskID) }
        }
    }

    public func cancel(_ taskID: String) async {
        guard let task = tasks[taskID], [.queued, .downloading, .paused].contains(task.state.status) else { return }
        await transport.cancel(taskID: taskID)
        var updated = task
        updated.apply(DownloadState(status: .failed, error: .cancelled))
        tasks[taskID] = updated
        try? fileManager.removeItem(at: task.destinationURL)
    }

    // MARK: - Event handling

    public func handle(_ event: DownloadEvent, taskID: String) async {
        guard var task = tasks[taskID] else { return }
        switch event {
        case let .progress(bytes, total):
            var state = task.state
            state.bytesDownloaded = bytes
            state.totalBytes = total
            task.apply(state)
            tasks[taskID] = task

        case let .completed(tempLocation):
            await finalize(task: &task, tempLocation: tempLocation)

        case let .failed(error):
            var state = task.state
            state.status = .failed
            state.error = error
            task.apply(state)
            tasks[taskID] = task
        }
    }

    // MARK: - Finalization / validation

    private func finalize(task: inout DownloadTask, tempLocation: URL) async {
        do {
            try task.state.transition(to: .finalizing)
        } catch {
            return
        }
        tasks[task.id] = task

        guard fileManager.fileExists(at: tempLocation), fileManager.size(of: tempLocation) > 0 else {
            fail(task: &task, with: .validationFailed)
            return
        }

        let destination = task.destinationURL
        let parent = destination.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(at: parent) {
                try fileManager.createDirectory(at: parent)
            }
            try fileManager.replaceItem(at: destination, withItemAt: tempLocation)
        } catch {
            fail(task: &task, with: .finalizationFailed)
            return
        }

        guard fileManager.fileExists(at: destination), fileManager.size(of: destination) > 0 else {
            fail(task: &task, with: .validationFailed)
            return
        }

        var completed = task.state
        completed.status = .completed
        completed.bytesDownloaded = completed.totalBytes
        task.apply(completed)
        tasks[task.id] = task
    }

    private func fail(task: inout DownloadTask, with error: DownloadError) {
        var state = task.state
        state.status = .failed
        state.error = error
        task.apply(state)
        tasks[task.id] = task
    }
}
