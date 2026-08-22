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
    /// (docs/03: at most two concurrent); promoted oldest-first.
    private struct PendingDownload {
        let videoID: String
        let title: String
        let channelTitle: String
        let quality: DownloadQuality
        let durationSeconds: TimeInterval
    }

    private var pendingRequests: [PendingDownload] = []

    private let extractor: MediaExtracting
    private let downloadManager: DownloadManager
    private let library: LibraryStore
    private let picker = DownloadQualityPicker()
    private let fileManager: FileManaging
    private let mediaDirectory: URL
    private let retryPolicy = DownloadRetryPolicy.default

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
        durationSeconds: TimeInterval = 0
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
                durationSeconds: durationSeconds
            )
        case let .adaptive(video, audio, resolution):
            await run(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, resolution: resolution, components: [video, audio],
                durationSeconds: durationSeconds
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
    /// final file can never be corrupted mid-write. Cancelling frees a logical
    /// download slot, so the oldest queued request is promoted.
    public func cancel(videoID: String, quality: DownloadQuality) async {
        await downloadManager.cancel("\(videoID)-\(quality.rawValue)")
        promoteNextPendingRequest()
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
        durationSeconds: TimeInterval
    ) async {
        var outcome = await runOnce(
            videoID: videoID, title: title, channelTitle: channelTitle,
            quality: quality, resolution: resolution, components: components,
            durationSeconds: durationSeconds
        )

        // Signed media URLs expire; one bounded automatic retry re-resolves
        // fresh stream URLs through the extractor before surfacing failure.
        // The decision consumes this run's LOCAL outcome, so a concurrent
        // download's failure can never cross-trigger (or suppress) a retry.
        if case let .failed(error) = outcome, retryPolicy.isRetryable(error) {
            guard let retried = try? await extractor.resolve(videoID: videoID) else {
                finish(outcome: .failed(.extractionFailed),
                       videoID: videoID, title: title, channelTitle: channelTitle, quality: quality)
                return
            }
            switch DownloadPlanner.plan(for: retried, quality: quality) {
            case let .combined(component, resolution):
                outcome = await runOnce(
                    videoID: videoID, title: title, channelTitle: channelTitle,
                    quality: quality, resolution: resolution, components: [component],
                    durationSeconds: durationSeconds
                )
            case let .adaptive(video, audio, resolution):
                outcome = await runOnce(
                    videoID: videoID, title: title, channelTitle: channelTitle,
                    quality: quality, resolution: resolution, components: [video, audio],
                    durationSeconds: durationSeconds
                )
            case .unavailable:
                outcome = .failed(.requestedQualityUnavailable)
            }
        }
        finish(outcome: outcome, videoID: videoID, title: title, channelTitle: channelTitle, quality: quality)
    }

    /// Single presentation point for a finished run: registers finalized media
    /// or surfaces the typed failure, then promotes queued work if a slot
    /// freed. `lastFailure` is only ever written here, from local outcomes.
    private func finish(
        outcome: RunOutcome,
        videoID: String,
        title: String,
        channelTitle: String,
        quality: DownloadQuality
    ) {
        switch outcome {
        case .completed:
            let destination = destination(videoID: videoID, quality: quality)
            library.addDownloadedMedia(DownloadedMedia(
                id: "\(videoID)-\(quality.rawValue)",
                videoID: videoID,
                title: title,
                channelTitle: channelTitle,
                resolution: quality.rawValue,
                fileURL: destination,
                sizeBytes: fileManager.size(of: destination),
                createdAt: Date()
            ))
        case let .failed(error):
            fail(videoID: videoID, title: title, quality: quality, error: error)
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
            promoteNextPendingRequest()
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
        durationSeconds: TimeInterval
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
        let enqueued = await downloadManager.enqueue(request, requiredBytes: requiredBytes)
        if enqueued.state.status == .failed {
            return .failed(enqueued.state.error ?? .storageRefused)
        }

        // The admission slot is already held (reserved in `download`, kept
        // across the automatic retry's re-enqueue of the same task id).
        downloadManager.setPresentationMetadata(taskID: id, title: title, channelTitle: channelTitle)

        // Capacity-deferred by the manager: persisted as `.queued` with no
        // coordinator task. Park it for FIFO promotion when a slot frees.
        if await downloadManager.coordinatorTask(id) == nil {
            downloadManager.releaseAdmission(id)
            pendingRequests.append(PendingDownload(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, durationSeconds: durationSeconds
            ))
            return .deferred
        }

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

    /// Promotes the oldest capacity-deferred request FIFO. Promotion goes back
    /// through `download`, which re-resolves fresh signed URLs — persisted
    /// component URLs are guaranteed expired by then. A promotion that still
    /// finds no free slot simply re-defers (no busy loop; runs per settle).
    private func promoteNextPendingRequest() {
        guard !pendingRequests.isEmpty else { return }
        let next = pendingRequests.removeFirst()
        Task { [weak self] in
            await self?.download(
                videoID: next.videoID,
                title: next.title,
                channelTitle: next.channelTitle,
                quality: next.quality,
                durationSeconds: next.durationSeconds
            )
        }
    }

    private func destination(videoID: String, quality: DownloadQuality) -> URL {
        mediaDirectory
            .appendingPathComponent(videoID)
            .appendingPathComponent("\(quality.rawValue)")
            .appendingPathComponent("media.mp4")
    }
}
