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

    /// Seeds cumulative progress for a freshly reattached task from its
    /// persisted record, so the UI projection doesn't restart at zero after a
    /// relaunch. The next cumulative `didWriteData` event supersedes these
    /// values.
    public func seedProgress(taskID: String, bytesDownloaded: Int64, totalBytes: Int64) {
        guard var task = tasks[taskID] else { return }
        var state = task.state
        state.bytesDownloaded = bytesDownloaded
        state.totalBytes = totalBytes
        task.apply(state)
        tasks[taskID] = task
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
        // A fresh (re-)enqueue starts a clean event chain; any straggler from a
        // previous generation keeps its own captured chain and cannot interleave.
        eventChains[request.id] = nil
        return task
    }

    /// Re-registers an externally-initiated (e.g. relaunched background session)
    /// task so its completion events drive the same state machine. `taskID` is
    /// the single source of truth: the stored task's id equals `taskID`.
    /// The direct `DownloadState(status:)` here is INITIALIZATION of a task
    /// that never existed in memory before — not a transition between
    /// observable states — so the transition table does not apply.
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
        // Weak self: a long-lived background transport holds this handler
        // until the transfer's terminal event (or cancel); it must not retain
        // the coordinator past that (HB-012).
        await transport.begin(request) { [weak self] event in
            Task { [weak self] in
                await self?.handle(event, taskID: taskID, onUpdate: onUpdate)
            }
        }
    }

    public func cancel(_ taskID: String) async {
        guard let task = tasks[taskID],
              [.queued, .downloading, .paused].contains(task.state.status) else { return }
        await transport.cancel(taskID: taskID)
        var updated = task
        // All guarded sources have legal .failed edges in the transition table
        // (HB-017): cancellation is an ordinary modeled transition, never a
        // bypass.
        var cancelledState = updated.state
        try? cancelledState.transition(to: .failed)
        cancelledState.error = .cancelled
        updated.apply(cancelledState)
        tasks[taskID] = updated
        removeComponentTemps(taskID)
        // Only an actively transferring task can have written toward the
        // destination. A queued/idle cancel of a re-enqueued id must preserve
        // the previous generation's finalized media, which the library record
        // still points at.
        if task.state.status == .downloading {
            try? fileManager.removeItem(at: task.destinationURL)
        }
        eventChains[taskID] = nil
    }

    /// Best-effort removal of staged component temp files so failed/cancelled
    /// attempts never orphan bytes in the incomplete-work area.
    private func removeComponentTemps(_ taskID: String) {
        for url in (componentTempLocations[taskID] ?? [:]).values {
            try? fileManager.removeItem(at: url)
        }
        componentTempLocations[taskID] = nil
        componentProgress[taskID] = nil
    }

    // MARK: - Event handling

    /// One link of a task's serialization chain (HB-006/HB-012): the handled
    /// event appends its node, awaits the previous node, applies inline on its
    /// own calling task, then signals its node. This keeps events applying in
    /// arrival order without allocating an unstructured Task per event, and the
    /// coordinator retains only the live tail node instead of every historical
    /// chain link.
    private final class EventChainNode: @unchecked Sendable {
        private let lock = NSLock()
        private var isSignaled = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        /// Returns once every earlier event in the chain has been applied.
        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if isSignaled {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }

        func signal() {
            lock.lock()
            isSignaled = true
            let waiters = self.waiters
            self.waiters = []
            lock.unlock()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    /// Per-task chain tail: each event's processing awaits the previous one,
    /// so events apply strictly in arrival order no matter which spawning Task
    /// the actor schedules first (HB-006). Without this, a late `.failed`
    /// could clobber a settled `.completed` state. Reset on enqueue/cancel so a
    /// fresh (re-)enqueue starts a clean chain; stragglers from a previous
    /// generation keep their captured nodes and cannot interleave into it.
    private var eventChains: [String: EventChainNode] = [:]

    public func handle(
        _ event: DownloadEvent,
        taskID: String,
        onUpdate: (@Sendable (DownloadTask) -> Void)? = nil
    ) async {
        let node = EventChainNode()
        // No suspension between reading and replacing the tail, so each call's
        // position in the chain is fixed atomically at actor entry.
        let previous = eventChains[taskID]
        eventChains[taskID] = node
        if let previous {
            await previous.wait()
        }
        await process(event, taskID: taskID, onUpdate: onUpdate)
        node.signal()
    }

    private func process(
        _ event: DownloadEvent,
        taskID: String,
        onUpdate: (@Sendable (DownloadTask) -> Void)?
    ) async {
        guard var task = tasks[taskID] else { return }
        // Settled jobs never accept further progress updates: late or
        // duplicate transport deliveries must not regress a terminal state's
        // final byte count. Terminal events (.failed) keep applying so the
        // last terminal in delivery order stays authoritative.
        if case .progress = event,
           task.state.status == .completed || task.state.status == .failed {
            return
        }
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
            // A settled completion is FINAL: a late transport failure after
            // genuine completion must not regress registered playable media
            // into a failed row (HB-017). Transports emit one terminal per
            // task; anything arriving after .completed is noise.
            guard task.state.status != .completed else { return }
            var state = task.state
            try? state.transition(to: .failed)
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
        if let updated = tasks[taskID] {
            onUpdate?(updated)
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
                // Unify with the validate-catch policy: no staged component
                // temp may outlive a failed finalization.
                removeComponentTemps(task.id)
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
                removeComponentTemps(task.id)
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
            removeComponentTemps(task.id)
            fail(task: &task, with: .muxFailed)
        }
    }

    private func complete(task: inout DownloadTask) {
        var completed = task.state
        try? completed.transition(to: .completed)
        completed.bytesDownloaded = completed.totalBytes
        completed.error = nil
        task.apply(completed)
        tasks[task.id] = task
    }

    private func fail(task: inout DownloadTask, with error: DownloadError) {
        var state = task.state
        // Finalize-path failures always originate from validating/muxing/
        // finalizing, all of which carry legal .failed edges (HB-017).
        try? state.transition(to: .failed)
        state.error = error
        task.apply(state)
        tasks[task.id] = task
    }
}
