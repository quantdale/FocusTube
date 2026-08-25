import Foundation
import FocusTubeCore

/// A user-observable download failure: which video+quality failed and the typed
/// `DownloadError` cause, plus a user-safe message (per docs/12, known causes
/// say what failed and whether retry can help — never a generic "unknown").
public struct DownloadFailure: Identifiable, Equatable, Sendable {
    public let videoID: String
    public let title: String
    public let quality: DownloadQuality
    public let error: DownloadError

    public var id: String { "\(videoID)-\(quality.rawValue)" }

    public var userMessage: String {
        switch error {
        case .extractionFailed:
            return "Couldn't extract media for this video. It may be unavailable or restricted; try again later."
        case .noAllowedStream:
            return "No downloadable stream is available for this video."
        case .requestedQualityUnavailable:
            return "\(quality.rawValue)p isn't available for this video. Choose another quality — quality is never downgraded."
        case .transportFailed:
            return "The download failed due to a network problem. Try again."
        case .expiredMediaURL:
            return "The media link expired. Starting the download again will fetch a fresh link."
        case .storageRefused:
            return "Not enough free storage to download this video. Free up space and try again."
        case .muxFailed:
            return "Combining the video and audio tracks failed. Try again."
        case .validationFailed:
            return "The downloaded file didn't pass validation and was discarded. Try again."
        case .finalizationFailed:
            return "Saving the downloaded file failed. Check available storage and try again."
        case .cancelled:
            return "The download was canceled."
        case .interrupted:
            return "The download was interrupted before it finished. You can retry it from Downloads."
        case .queueStateCorrupted:
            return "This queued download couldn't be restored after the app restarted. Start it again."
        case .unknown:
            return "The download failed for an unknown reason. Try again."
        }
    }
}

/// Orchestrates a real download: resolves media, selects the exact download
/// strategy for the chosen quality (combined, or adaptive video+audio mux),
/// drives `DownloadManager` over a durable background `URLSession`, and on
/// completion registers the finalized file in the `LibraryStore` so it appears
/// offline in the Downloads tab. The loop is: plan -> download -> finalize ->
/// register. No quality is ever silently downgraded, and every failure is
/// surfaced as a typed `DownloadFailure` on `lastFailure`.
@MainActor
@Observable
final class DownloadService {
    /// The most recent download failure, for UI to present and acknowledge.
    public private(set) var lastFailure: DownloadFailure?

    /// Result of one enqueue->begin->settle pass. Returned to `run` so retry
    /// decisions and presentation updates consume a LOCAL outcome — never the
    /// shared `lastFailure`, which concurrent downloads also write.
    private enum RunOutcome {
        case completed
        case failed(DownloadError)
        case timedOut
        case abandoned
        /// Deferred by the logical-concurrency limit: persisted as `.queued`,
        /// no transfer started; held for FIFO promotion.
        case deferred
    }

    /// Request parked because all logical download slots were taken
    /// (docs/03: at most two concurrent); promoted oldest-first. The same
    /// payload is persisted on the `.queued` record (`QueuedDownloadMetadata`)
    /// so the queue is reconstructable after process death.
    private struct PendingDownload {
        let taskID: String
        let videoID: String
        let title: String
        let channelTitle: String
        let quality: DownloadQuality
        let durationSeconds: TimeInterval
    }

    private var pendingRequests: [PendingDownload] = []
    /// Promotions already spawned but not yet settled. Keeps the bounded
    /// promotion loop from overshooting the concurrency budget while a
    /// promoted job's persisted record still reads `.queued`.
    private var promotingIDs: Set<String> = []

    /// Where a download invocation came from. Queue promotions bypass the
    /// FIFO-precedence rule at enqueue (they ARE the queue's head; sibling
    /// queued records sit behind them), keeping only the concurrency bound.
    enum Origin: Sendable {
        case userRequest
        case queuePromotion
    }

    private let extractor: MediaExtracting
    /// Internal for app-target deterministic tests (@testable).
    let downloadManager: DownloadManager
    /// Internal for app-target deterministic tests (@testable).
    let library: LibraryStore
    private let picker = DownloadQualityPicker()
    private let fileManager: FileManaging
    private let mediaDirectory: URL
    private let retryPolicy = DownloadRetryPolicy.default

    private static let settlementLogger = Logger(subsystem: "com.quantdale.FocusTube", category: "download-service")

    public init(
        extractor: MediaExtracting = YouTubeKitMediaExtractor(),
        downloadManager: DownloadManager,
        library: LibraryStore,
        fileManager: FileManaging = FileManager.default,
        mediaDirectory: URL = DownloadManager.defaultMediaDirectory()
    ) {
        self.extractor = extractor
        self.downloadManager = downloadManager
        self.library = library
        self.fileManager = fileManager
        self.mediaDirectory = mediaDirectory
    }

    public func download(
        videoID: String,
        title: String,
        channelTitle: String,
        quality: DownloadQuality,
        durationSeconds: TimeInterval = 0,
        origin: Origin = .userRequest
    ) async {
        // Synchronous duplicate admission: a second start for the same
        // video+quality would reset the coordinator's in-flight task to
        // .queued while the original transfer's events still arrive, corrupting
        // its state machine. `reserveAdmission` is checked-and-set on the main
        // actor before any await, so two rapid calls cannot both pass.
        guard downloadManager.reserveAdmission("\(videoID)-\(quality.rawValue)") else { return }

        // videoID comes from API JSON and becomes a filesystem path component
        // (`<mediaDirectory>/<videoID>/...`); reject anything outside the
        // YouTube ID alphabet before any work or path construction.
        guard DownloadRequest.isValidVideoID(videoID) else {
            downloadManager.releaseAdmission("\(videoID)-\(quality.rawValue)")
            fail(videoID: videoID, title: title, quality: quality, error: .validationFailed)
            return
        }

        // A stale `.queued` record for this exact id (e.g. one being promoted,
        // or a legacy row the user re-requested) is replaced by the fresh
        // pipeline run. Deleting it up front means an extraction/planning
        // failure below can never strand an orphaned queued row behind.
        downloadManager.clearStaleQueuedRecord("\(videoID)-\(quality.rawValue)")

        let media: ResolvedMedia
        do {
            media = try await extractor.resolve(videoID: videoID)
        } catch {
            downloadManager.releaseAdmission("\(videoID)-\(quality.rawValue)")
            fail(videoID: videoID, title: title, quality: quality, error: .extractionFailed)
            return
        }

        let plan = DownloadPlanner.plan(for: media, quality: quality)
        switch plan {
        case let .combined(component, resolution):
            await run(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, resolution: resolution, components: [component],
                durationSeconds: durationSeconds, origin: origin
            )
        case let .adaptive(video, audio, resolution):
            await run(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, resolution: resolution, components: [video, audio],
                durationSeconds: durationSeconds, origin: origin
            )
        case let .unavailable(reason):
            // The quality picker only offers qualities the planner can satisfy,
            // so this is defensive. No silent downgrade is performed.
            downloadManager.releaseAdmission("\(videoID)-\(quality.rawValue)")
            switch reason {
            case .noAllowedStream:
                fail(videoID: videoID, title: title, quality: quality, error: .noAllowedStream)
            case .requestedQualityUnavailable:
                fail(videoID: videoID, title: title, quality: quality, error: .requestedQualityUnavailable)
            }
        }
    }

    /// True while a transfer for this video+quality is admitted (synchronous
    /// reservation, including the pre-first-event window) or live in the
    /// manager's observable task projection.
    public func isInFlight(videoID: String, quality: DownloadQuality) -> Bool {
        downloadManager.startingIDs.contains("\(videoID)-\(quality.rawValue)") ||
            downloadManager.liveTasks.contains {
                $0.videoID == videoID && $0.resolution == quality.rawValue
            }
    }

    public func acknowledgeFailure() {
        lastFailure = nil
    }

    /// Cancels the live transfer for this video+quality via its canonical task
    /// id. Validating/muxing/finalizing phases are intentionally non-cancellable:
    /// the coordinator rejects cancel transitions out of those phases, so a
    /// final file can never be corrupted mid-write. Cancelling a QUEUED job
    /// deletes its durable record (manager-side). Either way a logical slot or
    /// queue position frees, so the oldest queued request is promoted.
    public func cancel(videoID: String, quality: DownloadQuality) async {
        let taskID = "\(videoID)-\(quality.rawValue)"
        pendingRequests.removeAll { $0.taskID == taskID }
        await downloadManager.cancel(taskID)
        await promoteQueuedWork()
    }

    private func fail(videoID: String, title: String, quality: DownloadQuality, error: DownloadError) {
        lastFailure = DownloadFailure(videoID: videoID, title: title, quality: quality, error: error)
    }

    private func run(
        videoID: String,
        title: String,
        channelTitle: String,
        quality: DownloadQuality,
        resolution: Int,
        components: [DownloadComponent],
        durationSeconds: TimeInterval,
        origin: Origin
    ) async {
        var outcome = await runOnce(
            videoID: videoID, title: title, channelTitle: channelTitle,
            quality: quality, resolution: resolution, components: components,
            durationSeconds: durationSeconds, origin: origin
        )

        // Signed media URLs expire; bounded automatic retries re-resolve
        // fresh stream URLs through the extractor before surfacing failure
        // (docs/03: up to three attempts total). The decision consumes this
        // run's LOCAL outcome, so a concurrent download's failure can never
        // cross-trigger (or suppress) a retry. The counter guarantees the
        // loop is structurally finite.
        var retriesRemaining = DownloadRetryPolicy.maxAutomaticRetries
        while case let .failed(error) = outcome, retriesRemaining > 0, retryPolicy.isRetryable(error) {
            retriesRemaining -= 1
            guard let retried = try? await extractor.resolve(videoID: videoID) else {
                outcome = .failed(.extractionFailed)
                break
            }
            switch DownloadPlanner.plan(for: retried, quality: quality) {
            case let .combined(component, resolution):
                outcome = await runOnce(
                    videoID: videoID, title: title, channelTitle: channelTitle,
                    quality: quality, resolution: resolution, components: [component],
                    durationSeconds: durationSeconds, origin: origin
                )
            case let .adaptive(video, audio, resolution):
                outcome = await runOnce(
                    videoID: videoID, title: title, channelTitle: channelTitle,
                    quality: quality, resolution: resolution, components: [video, audio],
                    durationSeconds: durationSeconds, origin: origin
                )
            case .unavailable:
                outcome = .failed(.requestedQualityUnavailable)
            }
        }
        await finish(
            outcome: outcome,
            videoID: videoID,
            title: title,
            channelTitle: channelTitle,
            quality: quality,
            origin: origin
        )
    }

    /// Single presentation point for a finished run: registers finalized media
    /// or surfaces the typed failure, then promotes queued work if a slot
    /// freed. HB-022 ownership rule: `lastFailure` is written ONLY for
    /// user-requested starts, so it can never carry a stale queue-promotion or
    /// background-settlement failure onto an unrelated video page. Promotion
    /// and reattached-path failures present where they belong — the Downloads
    /// surface's failed section (typed error + Retry row), which reads the
    /// persisted record projection.
    private func finish(
        outcome: RunOutcome,
        videoID: String,
        title: String,
        channelTitle: String,
        quality: DownloadQuality,
        origin: Origin
    ) async {
        // Any settled run (including defer/abandon/timeout) releases its
        // promotion reservation; real slots remain accounted by records.
        promotingIDs.remove("\(videoID)-\(quality.rawValue)")
        switch outcome {
        case .completed:
            let destination = destination(videoID: videoID, quality: quality)
            library.addDownloadedMedia(DownloadedMedia(
                id: "\(videoID)-\(quality.rawValue)",
                videoID: videoID,
                title: title,
                resolution: quality.rawValue,
                fileURL: destination,
                sizeBytes: fileManager.size(of: destination),
                createdAt: Date(),
                channelTitle: channelTitle
            ))
        case let .failed(error):
            // HB-022: only user-visible start attempts own the alert surface.
            // Queue promotions fail visibly as failed download rows instead.
            if origin == .userRequest {
                fail(videoID: videoID, title: title, quality: quality, error: error)
            } else {
                let taskID = "\(videoID)-\(quality.rawValue)"
                Self.settlementLogger.info(
                    "Promoted download \(taskID, privacy: .public) failed: \(error.rawValue, privacy: .public)"
                )
            }
        case .timedOut:
            // Timed out while still transferring: not a failure. The transfer
            // continues; its record and UI projection settle via events.
            break
        case .abandoned, .deferred:
            break
        }
        // Only a terminal outcome frees a logical slot; a deferred request
        // must not promote itself (it is still parked in the queue).
        switch outcome {
        case .completed, .failed:
            await promoteQueuedWork()
        case .timedOut, .abandoned, .deferred:
            break
        }
    }

    private func runOnce(
        videoID: String,
        title: String,
        channelTitle: String,
        quality: DownloadQuality,
        resolution: Int,
        components: [DownloadComponent],
        durationSeconds: TimeInterval,
        origin: Origin
    ) async -> RunOutcome {
        let id = "\(videoID)-\(quality.rawValue)"
        let request = DownloadRequest(
            id: id,
            videoID: videoID,
            resolution: resolution,
            destinationURL: destination(videoID: videoID, quality: quality),
            components: components
        )

        // Conservative up-front admission (docs/03): refuse before any partial
        // work when free space cannot plausibly hold the transfer. Unknown
        // durations estimate to 0 and skip the pre-check.
        let requiredBytes = StorageEstimator.requiredBytes(
            resolution: resolution,
            durationSeconds: durationSeconds,
            componentCount: components.count
        )
        let enqueued = await downloadManager.enqueue(
            request,
            requiredBytes: requiredBytes,
            queuedMetadata: QueuedDownloadMetadata(
                title: title,
                channelTitle: channelTitle,
                durationSeconds: durationSeconds
            ),
            bypassQueuePrecedence: origin == .queuePromotion,
            plannedDurationSeconds: durationSeconds > 0 ? durationSeconds : nil
        )
        if enqueued.state.status == .failed {
            return .failed(enqueued.state.error ?? .storageRefused)
        }

        // The admission slot is already held (reserved in `download`, kept
        // across the automatic retry's re-enqueue of the same task id).
        downloadManager.setPresentationMetadata(taskID: id, title: title, channelTitle: channelTitle)

        // Capacity-deferred by the manager: persisted as `.queued` with
        // durable planning metadata and no coordinator task/URLs. Park it for
        // FIFO promotion when a slot frees — in this process or, via record
        // reconstruction, after a relaunch.
        if await downloadManager.coordinatorTask(id) == nil {
            downloadManager.releaseAdmission(id)
            pendingRequests.append(PendingDownload(
                taskID: id,
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, durationSeconds: durationSeconds
            ))
            return .deferred
        }

        // Admitted: the record now carries the slot (`.resolving`), so the
        // promotion reservation must NOT keep double-counting this job in the
        // budget guard — otherwise a settled sibling can never promote while
        // this transfer runs.
        promotingIDs.remove(id)

        await downloadManager.begin(request.id)

        // Cancellation of the enclosing task (caller went away) stops polling
        // without touching download state; an explicit user cancel settles the
        // task through `cancel(videoID:quality:)` instead.
        let final: DownloadTask?
        do {
            final = try await downloadManager.waitForCompletion(request.id)
        } catch is CancellationError {
            return .abandoned
        } catch {
            return .failed(.unknown)
        }
        guard let final else { return .failed(.interrupted) }
        switch final.state.status {
        case .completed:
            return .completed
        case .failed:
            return .failed(final.state.error ?? .unknown)
        default:
            return .timedOut
        }
    }

    /// Promotes capacity-deferred requests FIFO. Promotion goes back through
    /// `download`, which re-resolves fresh signed URLs — persisted component
    /// URLs are never trusted (queued records persist none at all). The loop
    /// admits while the concurrency budget has room, counting both persisted
    /// active slots and in-flight promotions; a promotion that finds no room
    /// simply stays parked (re-defers onto the queue). Bounded by budget and
    /// queue length — never a busy loop.
    private func promoteQueuedWork() async {
        let maxConcurrent = DownloadManager.maxConcurrentDownloads
        while !pendingRequests.isEmpty {
            let counts = downloadManager.activeLogicalCounts()
            guard counts.active + promotingIDs.count < maxConcurrent else { break }
            let next = pendingRequests.removeFirst()
            promotingIDs.insert(next.taskID)
            Task { [weak self] in
                await self?.download(
                    videoID: next.videoID,
                    title: next.title,
                    channelTitle: next.channelTitle,
                    quality: next.quality,
                    durationSeconds: next.durationSeconds,
                    origin: .queuePromotion
                )
                self?.promotingIDs.remove(next.taskID)
            }
        }
    }

    /// Reconstructs the durable queue from persisted `.queued` records after a
    /// process relaunch (DDV2-01). Runs AFTER launch reconciliation so degraded
    /// corrupt rows are already settled out of the queue. Restored jobs are
    /// appended behind any session pendings only if not already present
    /// (dedupe by canonical task id), then promotion drains immediately when
    /// the budget has room — a relaunched app must not wait for an unrelated
    /// settle event to resume its own queued work.
    public func restorePersistedQueue() async {
        await downloadManager.reconcileOnLaunch()
        let known = Set(pendingRequests.map(\.taskID))
        for job in downloadManager.persistedQueuedJobs() where !known.contains(job.taskID) {
            guard let quality = DownloadQuality(rawValue: job.qualityRawValue) else { continue }
            pendingRequests.append(PendingDownload(
                taskID: job.taskID,
                videoID: job.videoID,
                title: job.title,
                channelTitle: job.channelTitle,
                quality: quality,
                durationSeconds: job.durationSeconds
            ))
        }
        await promoteQueuedWork()
    }

    /// Promotion trigger wired to `DownloadManager.onTaskSettled`: covers
    /// transfers whose run loop died with a previous process (reattached
    /// background settlement) as well as explicit cancels routed outside this
    /// service. Idempotent — duplicate triggers only re-attempt bounded
    /// promotion.
    public func downloadQueueDidSettle() {
        Task { await promoteQueuedWork() }
    }

    private func destination(videoID: String, quality: DownloadQuality) -> URL {
        mediaDirectory
            .appendingPathComponent(videoID)
            .appendingPathComponent("\(quality.rawValue)")
            .appendingPathComponent("media.mp4")
    }
}
