import Foundation
import SwiftData
import os
import FocusTubeCore
import AVFoundation

/// One durable queued job reconstructed from persisted state for FIFO
/// promotion after process death. Carries planning/presentation data only —
/// never media URLs, which are always re-resolved at promotion time.
public struct RestoredQueuedJob: Sendable {
    public let taskID: String
    public let videoID: String
    public let qualityRawValue: Int
    public let title: String
    public let channelTitle: String
    public let durationSeconds: TimeInterval
    public let createdAt: Date
}

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
    /// Invoked on the main actor whenever a task reaches ANY terminal status
    /// (completed/failed) through any path — live begin-loop events, cancel,
    /// or reattached background settlement. DownloadService wires this to its
    /// FIFO promotion trigger so a durable queued job is promoted even when
    /// the settling transfer belongs to a previous process lifetime (its own
    /// run loop died with it). Firing twice for one settle is harmless: the
    /// trigger only attempts bounded promotion.
    public var onTaskSettled: (@MainActor (DownloadTask) -> Void)?
    /// Cached UI projection of persisted `.queued` records, maintained at
    /// mutation points instead of refetching all records per render (HB-013).
    public private(set) var queuedTasks: [DownloadTask] = []
    /// Cached UI projection of persisted `.failed` records (HB-013).
    public private(set) var failedTasks: [DownloadTask] = []
    /// Memoized presentation metadata (HB-013): populated lazily, updated by
    /// writes; never re-fetches SwiftData during row renders.
    private var metadataCache: [String: (title: String?, channelTitle: String?)] = [:]

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
    /// Requests whose pre-attach buffer the active pass is currently draining.
    /// While set, live deliveries keep buffering so the drain stays the SINGLE
    /// ordered applier for the request; without this, the mailbox consumer
    /// could direct-route a stale delivery mid-replay and interleave it past
    /// newer buffered events (regressing cumulative bytes).
    private var replayingRequestIDs: Set<String> = []
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
        // Reattachment event delivery drains strictly sequentially so order
        // survives the hop.
        let (stream, continuation) = AsyncStream.makeStream(of: (requestID: String, event: DownloadEvent).self)
        self.reattachMailbox = stream
        self.reattachMailboxContinuation = continuation
        Task { [weak self] in
            for await (requestID, event) in stream {
                await self?.routeReattachedEvent(event, requestID: requestID)
            }
        }
        // NOTE: launch reconciliation is deliberately NOT spawned here. It is
        // awaited explicitly (RootView → DownloadService.restorePersistedQueue,
        // tests). An init-spawned pass would race rapid early enqueues —
        // freshly persisted `.resolving` rows can be mis-marked interrupted by
        // a late-running launch pass, corrupting admission accounting.
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
        // Durable-queue hygiene (DDV2-01): a persisted `.queued` record whose
        // identity or planning payload is unusable can never be promoted.
        // Degradation to a typed recoverable failure keeps it visible/actionable
        // instead of silently occupying the queue forever.
        let queuedStatus = DownloadStatus.queued.rawValue
        for record in records where record.statusRaw == queuedStatus {
            let usable = DownloadRequest.isValidVideoID(record.videoID)
                && DownloadQuality(rawValue: record.resolution) != nil
                && (record.queuedMetadataData == nil || record.queuedMetadata != nil)
            if !usable {
                degradeCorruptQueuedRecord(record)
            }
        }
        saveContext()
        refreshProjections()

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
                // From here until the drain below finishes, this request's
                // deliveries keep buffering (routeReattachedEvent honors the
                // replaying marker), so the drain is the single ordered
                // applier and arrival order survives every hop.
                replayingRequestIDs.insert(request.id)
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
                // Drain buffered deliveries until quiet, in arrival order. A
                // delivery that lands mid-drain buffers (replaying marker) and
                // is picked up by the next sweep; break+unmark happen without
                // an intervening await, so nothing can strand in the buffer.
                while true {
                    let buffered = reattachEventBuffer[request.id] ?? []
                    reattachEventBuffer[request.id] = nil
                    guard !buffered.isEmpty else { break }
                    for event in buffered {
                        await applyReattachedEvent(event, requestID: request.id)
                    }
                }
                replayingRequestIDs.remove(request.id)
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
        if attachedRequestIDs.contains(requestID) && !replayingRequestIDs.contains(requestID) {
            await applyReattachedEvent(event, requestID: requestID)
        } else {
            // Unknown to the coordinator yet, or its replay drain is still in
            // flight: buffer until the drain (or this request's pass) applies
            // it in arrival order.
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

    /// Upserts the DURABLE QUEUED state for a capacity-deferred request
    /// (DDV2-01): status `.queued`, no transfer components (never persists
    /// signed media URLs), and the planning payload promotion needs after
    /// process death. Re-deferrals of a previously admitted id are normalized
    /// too — a stale component list from an earlier attempt can never linger.
    private func persistQueuedState(_ task: DownloadTask, metadata: QueuedDownloadMetadata?) {
        do {
            let emptyComponents = Data("[]".utf8)
            if let existing = try recordOrThrow(id: task.id) {
                existing.apply(task)
                existing.componentsData = emptyComponents
                existing.bytesDownloaded = 0
                existing.totalBytes = 0
                existing.errorRaw = nil
                if let metadata { existing.applyQueuedMetadata(metadata) }
            } else {
                let record = DownloadRecord(task: task)
                record.componentsData = emptyComponents
                context.insert(record)
                if let metadata { record.applyQueuedMetadata(metadata) }
            }
            saveContext()
        } catch {
            Self.logger.fault("Record fetch failed during queued persistence (\(error.localizedDescription)); skipping")
        }
    }

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

    /// Snapshot of slot occupancy for admission/promotion decisions: how many
    /// records hold active slots and how many queued jobs precede new work.
    /// `.queued` records are deliberately EXCLUDED from `active`: they are
    /// parked intentions with no transfer, so a stranded queue delays
    /// promotion via the FIFO precedence rule but can never permanently
    /// consume the concurrency budget (DDV2-01).
    ///
    /// Counted in-store (`fetchCount`) instead of materializing every row:
    /// records persist forever once a download completes, so this warm path
    /// (every enqueue and promotion attempt) must not scale with lifetime
    /// download history.
    public func activeLogicalCounts() -> (active: Int, queued: Int) {
        let queuedStatus = DownloadStatus.queued.rawValue
        let completedStatus = DownloadStatus.completed.rawValue
        let failedStatus = DownloadStatus.failed.rawValue
        let idleStatus = DownloadStatus.idle.rawValue
        do {
            let activeDescriptor = FetchDescriptor<DownloadRecord>(
                predicate: #Predicate {
                    $0.statusRaw != queuedStatus && $0.statusRaw != completedStatus
                        && $0.statusRaw != failedStatus && $0.statusRaw != idleStatus
                }
            )
            let queuedDescriptor = FetchDescriptor<DownloadRecord>(
                predicate: #Predicate { $0.statusRaw == queuedStatus }
            )
            return (try context.fetchCount(activeDescriptor), try context.fetchCount(queuedDescriptor))
        } catch {
            Self.logger.fault("Record count failed during admission accounting (\(error.localizedDescription)); treating as empty")
            return (0, 0)
        }
    }

    /// Upserts the record for `task`; retries/re-resolutions reuse the same
    /// request id, and duplicate SwiftData records would corrupt
    /// reconciliation, so a failed record scan skips persistence instead of
    /// risking an insert.
    private func upsertRecord(_ task: DownloadTask) {
        do {
            if let existing = try recordOrThrow(id: task.id) {
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
    public func enqueue(
        _ request: DownloadRequest,
        requiredBytes: Int64 = 0,
        queuedMetadata: QueuedDownloadMetadata? = nil,
        bypassQueuePrecedence: Bool = false,
        plannedDurationSeconds: TimeInterval? = nil
    ) async -> DownloadTask {
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
        // logical downloads) with strict FIFO precedence: any already-queued
        // job forces deferral so later requests can never overtake it. At the
        // limit (or behind queued work) the request persists as `.queued`
        // WITH durable planning metadata and NO transfer; DownloadService
        // promotes it FIFO when a job settles or is cancelled — including
        // after a process relaunch, by reconstructing from these records.
        let counts = activeLogicalCounts()
        let deferred = bypassQueuePrecedence
            ? DownloadQueuePolicy.exceedsBudget(activeCount: counts.active, maxConcurrent: Self.maxConcurrentDownloads)
            : DownloadQueuePolicy.shouldDefer(
                activeCount: counts.active,
                queuedCount: counts.queued,
                maxConcurrent: Self.maxConcurrentDownloads
            )
        if deferred {
            // Signed component URLs are ephemeral and would be guaranteed-
            // expired by promotion time; queued rows persist NO URLs. The
            // promotion path re-resolves fresh streams through the extractor.
            let task = DownloadTask(
                id: request.id,
                videoID: request.videoID,
                resolution: request.resolution,
                destinationURL: request.destinationURL,
                components: [],
                state: DownloadState(status: .queued)
            )
            persistQueuedState(task, metadata: queuedMetadata)
            releaseAdmission(request.id)
            refreshProjections()
            return task
        }

        let task = await coordinator.enqueue(request)
        // Admitted ⇒ slot-consuming: persist the record as `.resolving`
        // immediately instead of the coordinator's pre-transfer `.queued`, so
        // capacity accounting reflects reality during the transfer (the
        // record otherwise lags until the first settle/event sync).
        var admitted = task
        if admitted.state.status == .queued {
            admitted.apply(DownloadState(status: .resolving))
        }
        upsertRecord(admitted)
        storePlannedDuration(taskID: request.id, seconds: plannedDurationSeconds)
        refreshProjections()
        return task
    }

    /// HB-023: persists the planning duration captured at enqueue so failed-row
    /// retries can re-run storage admission truthfully. Additive optional on
    /// the record; legacy rows read nil and keep the skip-pre-check behavior.
    private func storePlannedDuration(taskID: String, seconds: TimeInterval?) {
        guard let seconds else { return }
        do {
            guard let record = try recordOrThrow(id: taskID) else { return }
            record.plannedDurationSeconds = seconds
            plannedDurationCache[taskID] = .known(seconds)
            saveContext()
        } catch {
            Self.logger.fault("Record fetch failed while storing planned duration (\(error.localizedDescription))")
        }
    }

    /// The persisted planning duration for a failed row's retry; nil when
    /// unknown (legacy row or pre-HB-023 record).
    /// Memoized per task id (the value is written once at enqueue and never
    /// changes): the failed section reads this during row rendering, so each
    /// render must not re-fetch the records table.
    public func plannedDurationSeconds(taskID: String) -> TimeInterval? {
        if case let .known(seconds)? = plannedDurationCache[taskID] {
            return seconds
        }
        do {
            let seconds = try recordOrThrow(id: taskID)?.plannedDurationSeconds
            plannedDurationCache[taskID] = .known(seconds)
            return seconds
        } catch {
            Self.logger.fault("Record fetch failed while reading planned duration (\(error.localizedDescription))")
            return nil
        }
    }

    /// Memoization cell for `plannedDurationSeconds`: `.known(nil)` caches a
    /// legacy-row "unknown" so repeated renders never re-query it.
    private enum PlannedDurationEntry {
        case known(TimeInterval?)
    }

    private var plannedDurationCache: [String: PlannedDurationEntry] = [:]

    public func begin(_ taskID: String) async {
        await coordinator.begin(taskID) { [weak self] task in
            Task { @MainActor in
                self?.applyLive(task)
            }
        }
        await syncRecord(taskID)
    }

    /// Cancels a queued or live job. A QUEUED record has no transfer: it is
    /// deleted outright so a cancelled intention can neither promote later nor
    /// linger invisibly. Live transfers settle through the coordinator's
    /// typed cancelled failure, as before.
    public func cancel(_ taskID: String) async {
        if await coordinator.task(taskID) != nil {
            await coordinator.cancel(taskID)
            await syncRecord(taskID)
            if let settled = await coordinator.task(taskID),
               settled.state.status == .completed || settled.state.status == .failed {
                onTaskSettled?(settled)
            }
        } else if let record = try? recordOrThrow(id: taskID),
                  record.statusRaw == DownloadStatus.queued.rawValue {
            context.delete(record)
            saveContext()
            Self.logger.info("Cancelled queued download \(taskID, privacy: .public); record deleted")
        }
        removeLive(taskID)
        releaseAdmission(taskID)
        refreshProjections()
    }

    public var records: [DownloadTask] {
        fetchRecords().map { $0.downloadTask }
    }

    public var activeTasks: [DownloadTask] {
        records.filter { status in
            switch status.state.status {
            case .queued, .downloading, .paused, .validating, .muxing, .finalizing, .resolving:
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
            replaceProjection(task)
            onTaskSettled?(task)
        } else {
            replaceProjection(task)
        }
    }

    /// Maintains the cached queued/failed UI projections (HB-013)
    /// incrementally — no record fetches on per-event progress ticks.
    private func replaceProjection(_ task: DownloadTask) {
        removeFromProjections(task.id)
        switch task.state.status {
        case .queued:
            upsertIntoProjection(&queuedTasks, task)
        case .failed:
            upsertIntoProjection(&failedTasks, task)
        default:
            break
        }
    }

    private func upsertIntoProjection(_ projection: inout [DownloadTask], _ task: DownloadTask) {
        if let idx = projection.firstIndex(where: { $0.id == task.id }) {
            projection[idx] = task
        } else {
            projection.append(task)
        }
    }

    private func removeFromProjections(_ id: String) {
        queuedTasks.removeAll { $0.id == id }
        failedTasks.removeAll { $0.id == id }
    }

    /// Rebuilds both projections from persisted records in one fetch. Used at
    /// batch boundaries (reconciliation end, deletes), never per progress tick.
    public func refreshProjections() {
        let all = records
        let queuedStatus = DownloadStatus.queued.rawValue
        let failedStatus = DownloadStatus.failed.rawValue
        queuedTasks = all.filter { $0.state.status.rawValue == queuedStatus }
        failedTasks = all.filter { $0.state.status.rawValue == failedStatus }
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

    /// Store-filtered single-record lookup. Record lookups by id run on every
    /// enqueue/event-sync/metadata path, and rows accumulate for the app's
    /// lifetime, so each lookup filters in-store instead of materializing the
    /// whole table to scan it in memory.
    private func recordOrThrow(id: String) throws -> DownloadRecord? {
        var descriptor = FetchDescriptor<DownloadRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
            guard let record = try recordOrThrow(id: taskID) else { return }
            record.applyPresentationMetadata(title: title, channelTitle: channelTitle)
            metadataCache[taskID] = (title, channelTitle)
            saveContext()
        } catch {
            Self.logger.fault("Record fetch failed while storing presentation metadata (\(error.localizedDescription))")
        }
    }

    /// Reconstructs the durable FIFO queue from persisted `.queued` records,
    /// oldest first. Legacy rows without a queue payload are synthesized from
    /// their own fields (video id/resolution persisted; presentation strings
    /// fall back to the video id; duration unknown → 0, which only relaxes
    /// the storage pre-check). Unusable rows are skipped here — launch
    /// reconciliation degrades them to a typed failure.
    public func persistedQueuedJobs() -> [RestoredQueuedJob] {
        let queuedStatus = DownloadStatus.queued.rawValue
        let queuedRecords: [DownloadRecord]
        do {
            let descriptor = FetchDescriptor<DownloadRecord>(
                predicate: #Predicate { $0.statusRaw == queuedStatus }
            )
            queuedRecords = try context.fetch(descriptor)
        } catch {
            Self.logger.fault("Record fetch failed while restoring the durable queue (\(error.localizedDescription)); treating as empty")
            return []
        }
        let jobs: [RestoredQueuedJob] = queuedRecords.compactMap { record in
            guard record.statusRaw == queuedStatus else { return nil }
            guard DownloadRequest.isValidVideoID(record.videoID),
                  DownloadQuality(rawValue: record.resolution) != nil else { return nil }
            let metadata = record.queuedMetadata
            return RestoredQueuedJob(
                taskID: record.id,
                videoID: record.videoID,
                qualityRawValue: record.resolution,
                title: metadata?.title ?? record.title ?? record.videoID,
                channelTitle: metadata?.channelTitle ?? record.channelTitle ?? "",
                durationSeconds: metadata?.durationSeconds ?? 0,
                createdAt: record.createdAt
            )
        }
        return jobs.sorted { $0.createdAt < $1.createdAt }
    }

    /// Deletes any stale `.queued` record for `taskID` before a fresh
    /// pipeline run (promotion or retry) replaces its state. Without this, a
    /// promoted job whose extraction/planning fails would leave an orphaned
    /// queued row behind forever. Synchronous on the main actor; called with
    /// the admission slot already held, so no concurrent writer can exist.
    public func clearStaleQueuedRecord(_ taskID: String) {
        guard let record = try? recordOrThrow(id: taskID),
              record.statusRaw == DownloadStatus.queued.rawValue else { return }
        context.delete(record)
        saveContext()
        refreshProjections()
    }

    private func degradeCorruptQueuedRecord(_ record: DownloadRecord) {
        var state = DownloadState(status: .failed)
        state.error = .queueStateCorrupted
        let degraded = DownloadTask(
            id: record.id,
            videoID: record.videoID,
            resolution: record.resolution,
            destinationURL: record.destinationURL,
            components: [],
            state: state
        )
        record.apply(degraded)
        releaseAdmission(record.id)
        Self.logger.fault(
            "Persisted queued download \(record.id, privacy: .public) has unusable identity/metadata; degraded to recoverable failure"
        )
    }

    /// Lookup of stored presentation metadata; nil when the record is unknown.
    /// `title` itself may be nil for legacy rows created before the additive
    /// fields existed — callers fall back to the videoID.
    ///
    /// Served from the enqueue-time cache when present (HB-013); a miss does
    /// ONE store-filtered row fetch and backfills the cache. Unknown ids are
    /// never cached negatively: a record could still be inserted later by the
    /// admission path. DownloadsView reads this per rendered row, so before
    /// this memoization every progress tick re-fetched the records table once
    /// per visible row.
    public func presentationMetadata(taskID: String) -> (title: String?, channelTitle: String?)? {
        if let cached = metadataCache[taskID] {
            return cached
        }
        let record: DownloadRecord?
        do {
            record = try recordOrThrow(id: taskID)
        } catch {
            Self.logger.fault("Record fetch failed while reading presentation metadata (\(error.localizedDescription))")
            return nil
        }
        guard let record else { return nil }
        let metadata = (record.title, record.channelTitle)
        metadataCache[taskID] = metadata
        return metadata
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
            record = try recordOrThrow(id: taskID)
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
        replaceProjection(task)
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
