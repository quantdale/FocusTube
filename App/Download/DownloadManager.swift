import Foundation
import SwiftData
import os
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
    /// Synchronous duplicate-admission set: task IDs are reserved before any
    /// await (`reserveAdmission`, called by DownloadService and at the top of
    /// `enqueue`) and released only at terminal settle/cancel, so two rapid
    /// download requests cannot both pass an async `liveTasks` check and
    /// double-start the same transfer.
    public private(set) var startingIDs: Set<String> = []
    /// Maximum concurrently admitted logical downloads (docs/03). Additional
    /// requests persist as `.queued` without starting a transfer and are
    /// promoted FIFO by DownloadService when a job settles or is cancelled.
    static let maxConcurrentDownloads = 2
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "download-manager")

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
    /// Reattached-transfer events that arrive after handler registration but
    /// before their request is re-registered with the coordinator, where
    /// `handle` would silently drop them (unknown task). Buffered on the main
    /// actor during reconciliation and replayed once the request attaches.
    private var reattachEventBuffer: [String: [DownloadEvent]] = [:]
    /// Requests whose transfers are registered with the coordinator.
    /// Persistent across reconciliation passes: once a request is attached,
    /// its live events route straight through, and later passes never re-run
    /// its attach/seed/replay sequence — no duplicate reattachment side
    /// effects, no stale persisted bytes regressing applied progress.
    private var attachedRequestIDs: Set<String> = []
    /// Single-flight reconciliation: overlapping callers coalesce into the
    /// active pass instead of racing their own reattachment, and once a pass
    /// has completed every later caller returns immediately — launch
    /// reconciliation runs exactly once per manager lifetime. A second pass
    /// could only double-fire transport reattachment (duplicate event
    /// delivery) and duplicate attach/seed side effects, never add coverage.
    private var reconciliationActive = false
    private var hasReconciled = false
    private var reconcileWaiters: [CheckedContinuation<Void, Never>] = []
    /// Ordered delivery channel for reattached-transfer events (H2-005).
    /// The URLSession delegate queue yields synchronously, so stream order
    /// equals delegate delivery order; the single init-spawned consumer is
    /// the only caller of `routeReattachedEvent`, so no unstructured Task can
    /// scramble progress/terminal sequencing before coordinator serialization.
    private let reattachMailbox: AsyncStream<(requestID: String, event: DownloadEvent)>
    private let reattachMailboxContinuation: AsyncStream<(requestID: String, event: DownloadEvent)>.Continuation

    public init(
        transport: DownloadTransport,
        context: ModelContext,
        storage: StorageProviding = VolumeStorage(),
        mediaDirectory: URL = DownloadManager.defaultMediaDirectory(),
        incompleteDirectory: URL = DownloadManager.defaultIncompleteDirectory(),
        validate: (@Sendable (URL) async throws -> Void)? = MediaAssetValidator.makeSeam()
    ) {
        self.context = context
        self.storage = storage
        self.mediaDirectory = mediaDirectory
        self.incompleteDirectory = incompleteDirectory
        self.transport = transport
        self.coordinator = DownloadCoordinator(
            transport: transport,
            directory: incompleteDirectory,
            mux: Self.makeMux(),
            validate: validate
        )
        // Reconciliation awaits transport reattachment, so it runs as a task;
        // `reconcileOnLaunch()` is single-flight and may also be awaited
        // directly — overlapping callers coalesce into the active pass.
        // The mailbox consumer must exist before reconciliation can deliver,
        // and drains strictly sequentially so event order survives the hop.
        let (stream, continuation) = AsyncStream.makeStream(of: (requestID: String, event: DownloadEvent).self)
        self.reattachMailbox = stream
        self.reattachMailboxContinuation = continuation
        Task { [weak self] in
            for await (requestID, event) in stream {
                await self?.routeReattachedEvent(event, requestID: requestID)
            }
        }
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
    /// retryable. Idempotent for already-attached tasks and settled records.
    ///
    /// Single flight, exactly one pass per manager lifetime: the init-spawned
    /// launch task plus any explicit await coalesce into that pass; later
    /// callers return immediately because the completed pass fully covered
    /// them. Overlapping passes would race on shared buffer/attachment
    /// bookkeeping and fire transport reattachment twice.
    public func reconcileOnLaunch() async {
        if reconciliationActive {
            // Join the active pass; it covers this caller too.
            await withCheckedContinuation { reconcileWaiters.append($0) }
            return
        }
        guard !hasReconciled else { return }
        reconciliationActive = true
        defer {
            reconciliationActive = false
            hasReconciled = true
            let parked = reconcileWaiters
            reconcileWaiters.removeAll()
            for waiter in parked {
                waiter.resume()
            }
        }
        await performReconciliation()
    }

    /// One serialized reconciliation pass. Runs only under the single-flight
    /// gate held by `reconcileOnLaunch()`.
    private func performReconciliation() async {
        reattachEventBuffer.removeAll()
        let recovered = await transport.reattach { [weak self] requestID, event in
            // Synchronous yield on the serial delegate queue preserves
            // URLSession delivery order (H2-005); the mailbox consumer applies
            // events one at a time in exactly that order.
            self?.reattachMailboxContinuation.yield((requestID, event))
        }
        sweepMuxingOrphans()
        let recoveredByID = Dictionary(recovered.map { ($0.requestID, $0) }, uniquingKeysWith: { first, _ in first })

        // A failed record fetch must not be treated as "no records": that
        // would cancel recovered transfers as unrecorded. Conservative branch:
        // skip this reconciliation iteration entirely (logged); recovered
        // transfers keep running untouched.
        let records: [DownloadRecord]
        do {
            records = try fetchRecordsOrThrow()
        } catch {
            Self.logger.fault("Record fetch failed during launch reconciliation (\(error.localizedDescription)); skipping iteration")
            return
        }
        let tasks = records.map { $0.downloadTask }
        let reconciled = DownloadReconciler.reconcile(tasks) { [weak self] url in
            self?.fileExists(url) ?? false
        } sizeOf: { [weak self] url in
            self?.fileSize(url) ?? 0
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
            if task.state.status == .completed || task.state.status == .failed {
                releaseAdmission(record.id)
            }
        }
        saveContext()

        for record in records {
            guard let info = recoveredByID[record.id] else { continue }
            if info.isPartialRecovery(componentCount: record.components.count) {
                // Some components died with the previous process, so the job
                // can never finalize. Cancel the surviving transfers so the
                // background session drains instead of feeding a doomed job.
                await transport.cancel(taskID: record.id)
                reattachEventBuffer[record.id] = nil
            } else {
                // Already registered by an earlier pass: live events flow
                // straight through now. Re-attaching/re-seeding would double
                // side effects and regress newer applied progress.
                guard !attachedRequestIDs.contains(record.id) else { continue }
                let request = DownloadRequest(
                    id: record.id,
                    videoID: record.videoID,
                    resolution: record.resolution,
                    destinationURL: record.destinationURL,
                    components: record.components
                )
                await coordinator.attach(taskID: request.id, request: request)
                attachedRequestIDs.insert(request.id)
                // Seed cumulative progress from the persisted record so the UI
                // doesn't restart at zero after relaunch; the next cumulative
                // didWriteData event supersedes these values.
                let persisted = record.downloadTask.state
                if persisted.bytesDownloaded > 0 || persisted.totalBytes > 0 {
                    await coordinator.seedProgress(
                        taskID: request.id,
                        bytesDownloaded: persisted.bytesDownloaded,
                        totalBytes: persisted.totalBytes
                    )
                    await persistTaskSnapshot(request.id)
                }
                // Replay any events that landed between handler registration
                // and this attach, in arrival order.
                if let buffered = reattachEventBuffer[request.id] {
                    reattachEventBuffer[request.id] = nil
                    for event in buffered {
                        await applyReattachedEvent(event, requestID: request.id)
                    }
                }
            }
        }
        // A recovered transfer without a persisted record would stream orphaned
        // bytes forever; cancel it so the background session drains.
        let recordedIDs = Set(records.map(\.id))
        for requestID in recoveredByID.keys where !recordedIDs.contains(requestID) {
            await transport.cancel(taskID: requestID)
            reattachEventBuffer[requestID] = nil
        }
    }

    /// Routes a reattached transfer event: straight through once its request is
    /// registered with the coordinator, buffered while reconciliation is still
    /// attaching it.
    private func routeReattachedEvent(_ event: DownloadEvent, requestID: String) async {
        if attachedRequestIDs.contains(requestID) {
            await applyReattachedEvent(event, requestID: requestID)
        } else {
            // Unknown to the coordinator yet: buffer until this request's pass
            // attaches it and replays the buffer in arrival order.
            reattachEventBuffer[requestID, default: []].append(event)
        }
    }

    private func applyReattachedEvent(_ event: DownloadEvent, requestID: String) async {
        await coordinator.handle(event, taskID: requestID)
        await persistTaskSnapshot(requestID)
    }

    /// Removes stale `.muxing-` intermediates from the incomplete-work area.
    /// A mux output exists only while an adaptive export runs within one
    /// process lifetime (it is moved into place or deleted before the job
    /// settles), so after a relaunch it can never be consumed — sweep it so
    /// interrupted exports don't leak bytes.
    private func sweepMuxingOrphans() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: incompleteDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.lastPathComponent.contains(".muxing-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Control

    /// Synchronous admission check for a download request. Returns false when
    /// a transfer for this task id is already admitted and not yet settled —
    /// including the window between `enqueue` acceptance and the first live
    /// progress event, where `liveTasks` is not yet populated. Callers must
    /// invoke this before any await for the guarantee to hold.
    @discardableResult
    public func reserveAdmission(_ taskID: String) -> Bool {
        if startingIDs.contains(taskID) { return false }
        startingIDs.insert(taskID)
        return true
    }

    public func releaseAdmission(_ taskID: String) {
        startingIDs.remove(taskID)
    }

    /// Number of persisted records in a non-terminal status; used for the
    /// logical-concurrency admission limit.
    private func activeLogicalCount() -> Int {
        do {
            let terminal: Set<String> = [
                DownloadStatus.completed.rawValue,
                DownloadStatus.failed.rawValue,
                DownloadStatus.idle.rawValue
            ]
            return try fetchRecordsOrThrow().filter { !terminal.contains($0.statusRaw) }.count
        } catch {
            // Availability over stall: an unreadable index must not silently
            // wedge all future downloads; duplicates are still prevented by
            // `reserveAdmission`. Logged loudly for diagnosis.
            Self.logger.fault("Record fetch failed during capacity check (\(error.localizedDescription)); admitting")
            return 0
        }
    }

    /// Upserts the record for `task`; retries/re-resolutions reuse the same
    /// request id, and duplicate SwiftData records would corrupt
    /// reconciliation, so a failed record scan skips persistence instead of
    /// risking an insert.
    private func upsertRecord(_ task: DownloadTask) {
        do {
            if let existing = try fetchRecordsOrThrow().first(where: { $0.id == task.id }) {
                existing.apply(task)
            } else {
                context.insert(DownloadRecord(task: task))
            }
            saveContext()
        } catch {
            Self.logger.fault("Record fetch failed during upsert (\(error.localizedDescription)); skipping persistence")
        }
    }

    @discardableResult
    public func enqueue(_ request: DownloadRequest, requiredBytes: Int64 = 0) async -> DownloadTask {
        startingIDs.insert(request.id)

        func refused(_ error: DownloadError) -> DownloadTask {
            let task = DownloadTask(
                id: request.id,
                videoID: request.videoID,
                resolution: request.resolution,
                destinationURL: request.destinationURL,
                components: request.components,
                state: DownloadState(status: .failed, error: error)
            )
            upsertRecord(task)
            releaseAdmission(request.id)
            return task
        }

        if requiredBytes > 0 && requiredBytes > storage.availableCapacity(for: request.destinationURL) {
            return refused(.storageRefused)
        }

        // Logical concurrency admission (docs/03: at most two concurrent
        // logical downloads). At the limit the request persists as `.queued`
        // without contacting the coordinator; DownloadService promotes it FIFO
        // when a job settles or is cancelled.
        if activeLogicalCount() >= Self.maxConcurrentDownloads {
            let task = DownloadTask(
                id: request.id,
                videoID: request.videoID,
                resolution: request.resolution,
                destinationURL: request.destinationURL,
                components: request.components,
                state: DownloadState(status: .queued)
            )
            upsertRecord(task)
            releaseAdmission(request.id)
            return task
        }

        let task = await coordinator.enqueue(request)
        upsertRecord(task)
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
        releaseAdmission(taskID)
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

    /// Waits until the coordinator reports the task settled (`.completed` or
    /// `.failed`). Throws `CancellationError` when the enclosing task is
    /// cancelled, so dismissed callers stop polling without mutating download
    /// state. When the timeout elapses while the transfer is still active, the
    /// current task is returned as-is: the transfer keeps running and may still
    /// complete (its record settles through the normal event path), which must
    /// not surface as a false failure. Returns nil only when no such task exists.
    public func waitForCompletion(_ id: String, timeout: TimeInterval = 600) async throws -> DownloadTask? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let task = await coordinator.task(id),
               task.state.status == .completed || task.state.status == .failed {
                await syncRecord(id)
                return task
            }
            try Task.checkCancellation()
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
            releaseAdmission(task.id)
        }
    }

    private func removeLive(_ taskID: String) {
        liveTasks.removeAll { $0.id == taskID }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            Self.logger.fault("SwiftData save failed (\(error.localizedDescription)) for task state")
        }
    }

    // MARK: - Helpers

    private func fetchRecordsOrThrow() throws -> [DownloadRecord] {
        try context.fetch(FetchDescriptor<DownloadRecord>())
    }

    /// Non-decisional convenience: for display/diagnostic reads where an
    /// empty result is safe. Decision paths use `fetchRecordsOrThrow`.
    private func fetchRecords() -> [DownloadRecord] {
        do {
            return try fetchRecordsOrThrow()
        } catch {
            Self.logger.fault("Record fetch failed (\(error.localizedDescription)); returning empty")
            return []
        }
    }

    /// Persists user-facing presentation metadata (title/channel) captured at
    /// enqueue time so background-completed downloads register in the library
    /// with real titles instead of the videoID placeholder.
    public func setPresentationMetadata(taskID: String, title: String, channelTitle: String) {
        do {
            guard let record = try fetchRecordsOrThrow().first(where: { $0.id == taskID }) else { return }
            record.applyPresentationMetadata(title: title, channelTitle: channelTitle)
            saveContext()
        } catch {
            Self.logger.fault("Record fetch failed while storing presentation metadata (\(error.localizedDescription))")
        }
    }

    /// Lookup of stored presentation metadata; nil when the record is unknown.
    /// `title` itself may be nil for legacy rows created before the additive
    /// fields existed — callers fall back to the videoID.
    public func presentationMetadata(taskID: String) -> (title: String?, channelTitle: String?)? {
        let record: DownloadRecord?
        do {
            record = try fetchRecordsOrThrow().first(where: { $0.id == taskID })
        } catch {
            Self.logger.fault("Record fetch failed while reading presentation metadata (\(error.localizedDescription))")
            return nil
        }
        guard let record else { return nil }
        return (record.title, record.channelTitle)
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    private func syncRecord(_ taskID: String) async {
        let record: DownloadRecord?
        do {
            record = try fetchRecordsOrThrow().first(where: { $0.id == taskID })
        } catch {
            Self.logger.fault("Record fetch failed during sync (\(error.localizedDescription)); skipping persistence")
            return
        }
        guard let record else { return }
        guard let task = await coordinator.task(taskID) else { return }
        record.apply(task)
        if task.state.status == .completed || task.state.status == .failed {
            releaseAdmission(taskID)
        }
        saveContext()
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
            releaseAdmission(taskID)
            onMediaFinalized?(task)
        }
    }
}
