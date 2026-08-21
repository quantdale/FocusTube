import Foundation

/// Owns the explicit download state machine, finalization, and validation for
/// all download jobs. Network and filesystem behavior are injected via
/// `DownloadTransport` / `FileManaging` seams so the policy is deterministically
/// testable without real transfers.
///
/// A job may carry one component (a combined stream) or two (an adaptive
/// video-only + audio-only pair). Multi-component jobs download every component
/// in parallel, validate them, then for the adaptive case combine them via the
/// injected `mux` closure (native AVFoundation in the app) into a transient
/// file and move it into place, so an interrupted export never leaves a
/// playable-looking partial final. Single-component finalization is atomic via
/// `FileManaging.replaceItem`.
public actor DownloadCoordinator {
    private var tasks: [String: DownloadTask]
    private let transport: DownloadTransport
    private let fileManager: FileManaging
    private let directory: URL
    private let mux: (@Sendable ([URL], URL) async throws -> URL)?
    /// Optional deep-validation seam (e.g. native AVFoundation asset checks in
    /// the app layer) run against the finalized file before a job completes.
    /// Throwing marks the job `.validationFailed`; Core itself keeps no
    /// AVFoundation dependency.
    private let validate: (@Sendable (URL) async throws -> Void)?

    /// Transient per-component state for in-flight jobs.
    private var componentTempLocations: [String: [Int: URL]] = [:]
    private var componentProgress: [String: [Int: (bytes: Int64, total: Int64)]] = [:]

    public init(
        transport: DownloadTransport,
        fileManager: FileManaging = FileManager.default,
        directory: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FocusTubeDownloads"),
        mux: (@Sendable ([URL], URL) async throws -> URL)? = nil,
        validate: (@Sendable (URL) async throws -> Void)? = nil
    ) {
        self.transport = transport
        self.fileManager = fileManager
        self.directory = directory
        self.mux = mux
        self.validate = validate
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
            resolution: request.resolution,
            destinationURL: request.destinationURL,
            components: request.components
        )
        task.apply(DownloadState(status: .queued))
        tasks[request.id] = task
        componentTempLocations[request.id] = [:]
        componentProgress[request.id] = [:]
        return task
    }

    /// Re-registers an externally-initiated (e.g. relaunched background session)
    /// task so its completion events drive the same state machine. `taskID` is
    /// the single source of truth: the stored task's id equals `taskID`.
    public func attach(taskID: String, request: DownloadRequest) {
        guard tasks[taskID] == nil else { return }
        var task = DownloadTask(
            id: taskID,
            videoID: request.videoID,
            resolution: request.resolution,
            destinationURL: request.destinationURL,
            components: request.components
        )
        task.apply(DownloadState(status: .downloading))
        tasks[taskID] = task
        componentTempLocations[taskID] = [:]
        componentProgress[taskID] = [:]
    }

    public func begin(_ taskID: String, onUpdate: (@Sendable (DownloadTask) -> Void)? = nil) async {
        guard let task = tasks[taskID], task.state.status == .queued else { return }
        var updated = task
        do {
            try updated.transition(to: .downloading)
        } catch {
            return
        }
        tasks[taskID] = updated

        let request = DownloadRequest(
            id: task.id,
            videoID: task.videoID,
            resolution: task.resolution,
            destinationURL: task.destinationURL,
            components: task.components
        )
        await transport.begin(request) { [self] event in
            Task { [self] in
                await self.handle(event, taskID: taskID)
                if let current = await self.task(taskID) {
                    onUpdate?(current)
                }
            }
        }
    }

    public func cancel(_ taskID: String) async {
        guard let task = tasks[taskID],
              [.queued, .downloading, .paused, .waitingForRetry, .reResolving].contains(task.state.status) else { return }
        await transport.cancel(taskID: taskID)
        var updated = task
        updated.apply(DownloadState(status: .failed, error: .cancelled))
        tasks[taskID] = updated
        for url in (componentTempLocations[taskID] ?? [:]).values {
            try? fileManager.removeItem(at: url)
        }
        componentTempLocations[taskID] = nil
        componentProgress[taskID] = nil
        try? fileManager.removeItem(at: task.destinationURL)
    }

    // MARK: - Event handling

    public func handle(_ event: DownloadEvent, taskID: String) async {
        guard var task = tasks[taskID] else { return }
        switch event {
        case let .progress(component, bytes, total):
            var dict = componentProgress[taskID] ?? [:]
            dict[component] = (bytes, total)
            componentProgress[taskID] = dict
            let aggregate = dict.values.reduce((Int64(0), Int64(0))) { acc, v in
                (acc.0 + v.bytes, acc.1 + v.total)
            }
            var state = task.state
            state.bytesDownloaded = aggregate.0
            state.totalBytes = aggregate.1
            task.apply(state)
            tasks[taskID] = task

        case let .completed(tempLocation, component):
            var dict = componentTempLocations[taskID] ?? [:]
            dict[component] = tempLocation
            componentTempLocations[taskID] = dict
            if dict.count == task.components.count {
                let ordered = task.components.indices.compactMap { dict[$0] }
                await finalize(task: &task, tempLocations: ordered)
            }

        case let .failed(error):
            var state = task.state
            state.status = .failed
            state.error = error
            task.apply(state)
            tasks[taskID] = task
            // Remove any component temp files staged for this job so failed
            // attempts never orphan bytes in the incomplete-work area.
            for url in (componentTempLocations[taskID] ?? [:]).values {
                try? fileManager.removeItem(at: url)
            }
            componentTempLocations[taskID] = nil
            componentProgress[taskID] = nil
        }
    }

    // MARK: - Finalization / validation

    private func finalize(task: inout DownloadTask, tempLocations: [URL]) async {
        do {
            try task.transition(to: .validating)
        } catch {
            return
        }
        tasks[task.id] = task

        for location in tempLocations {
            guard fileManager.fileExists(at: location), fileManager.size(of: location) > 0 else {
                fail(task: &task, with: .validationFailed)
                return
            }
        }

        let destination = task.destinationURL
        let parent = destination.deletingLastPathComponent()

        if tempLocations.count == 1 {
            do {
                try task.transition(to: .finalizing)
            } catch {
                return
            }
            tasks[task.id] = task
            do {
                if !fileManager.fileExists(at: parent) {
                    try fileManager.createDirectory(at: parent)
                }
                // replaceItemAt requires an existing destination; first-time
                // downloads move the temp file into the empty slot instead.
                if fileManager.fileExists(at: destination) {
                    try fileManager.replaceItem(at: destination, withItemAt: tempLocations[0])
                } else {
                    try fileManager.moveItem(at: tempLocations[0], to: destination)
                }
            } catch {
                fail(task: &task, with: .finalizationFailed)
                return
            }
            guard fileManager.fileExists(at: destination), fileManager.size(of: destination) > 0 else {
                fail(task: &task, with: .validationFailed)
                return
            }
            if let validate {
                do {
                    try await validate(destination)
                } catch {
                    // A file that fails deep validation is discarded, never
                    // registered as a playable download.
                    try? fileManager.removeItem(at: destination)
                    fail(task: &task, with: .validationFailed)
                    return
                }
            }
            complete(task: &task)
            return
        }

        // Adaptive path: combine components into the final file.
        do {
            try task.transition(to: .muxing)
        } catch {
            return
        }
        tasks[task.id] = task

        guard let mux else {
            fail(task: &task, with: .muxFailed)
            return
        }
        // Mux into a transient sibling of the work directory, never directly
        // into the destination: an interrupted export must not leave a
        // playable-looking partial final, and exporting over an existing file
        // makes AVAssetExportSession unreliable on re-download.
        let muxOutput = directory.appendingPathComponent(
            destination.lastPathComponent + ".muxing-" + UUID().uuidString
        )
        do {
            if !fileManager.fileExists(at: parent) {
                try fileManager.createDirectory(at: parent)
            }
            if !fileManager.fileExists(at: directory) {
                try fileManager.createDirectory(at: directory)
            }
            let output = try await mux(tempLocations, muxOutput)
            guard fileManager.fileExists(at: output), fileManager.size(of: output) > 0 else {
                try? fileManager.removeItem(at: output)
                fail(task: &task, with: .validationFailed)
                return
            }
            do {
                try task.transition(to: .finalizing)
            } catch {
                return
            }
            tasks[task.id] = task
            // Publish atomically: clear any stale destination, then move the
            // validated mux product into place.
            do {
                if fileManager.fileExists(at: destination) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: output, to: destination)
            } catch {
                try? fileManager.removeItem(at: output)
                fail(task: &task, with: .finalizationFailed)
                return
            }
            // The final file is published from the component temps; remove the
            // transient files so nothing is orphaned in the work directory.
            // (The single-component path moves its temp via replaceItem.)
            if let validate {
                do {
                    try await validate(destination)
                } catch {
                    // Discard a mux product that fails deep validation along
                    // with its component temps; nothing may register.
                    try? fileManager.removeItem(at: destination)
                    for location in tempLocations {
                        try? fileManager.removeItem(at: location)
                    }
                    fail(task: &task, with: .validationFailed)
                    return
                }
            }
            for location in tempLocations {
                try? fileManager.removeItem(at: location)
            }
            complete(task: &task)
        } catch {
            try? fileManager.removeItem(at: muxOutput)
            fail(task: &task, with: .muxFailed)
        }
    }

    private func complete(task: inout DownloadTask) {
        var completed = task.state
        completed.status = .completed
        completed.bytesDownloaded = completed.totalBytes
        completed.error = nil
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
