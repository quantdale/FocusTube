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
public final class DownloadService {
    /// The most recent download failure, for UI to present and acknowledge.
    public private(set) var lastFailure: DownloadFailure?

    private let extractor: MediaExtracting
    private let downloadManager: DownloadManager
    private let library: LibraryStore
    private let picker = DownloadQualityPicker()
    private let fileManager: FileManaging
    private let mediaDirectory: URL

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
        quality: DownloadQuality
    ) async {
        let media: ResolvedMedia
        do {
            media = try await extractor.resolve(videoID: videoID)
        } catch {
            fail(videoID: videoID, title: title, quality: quality, error: .extractionFailed)
            return
        }

        let plan = DownloadPlanner.plan(for: media, quality: quality)
        switch plan {
        case let .combined(component, resolution):
            await run(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, resolution: resolution, components: [component]
            )
        case let .adaptive(video, audio, resolution):
            await run(
                videoID: videoID, title: title, channelTitle: channelTitle,
                quality: quality, resolution: resolution, components: [video, audio]
            )
        case let .unavailable(reason):
            // The quality picker only offers qualities the planner can satisfy,
            // so this is defensive. No silent downgrade is performed.
            switch reason {
            case .noAllowedStream:
                fail(videoID: videoID, title: title, quality: quality, error: .noAllowedStream)
            case .requestedQualityUnavailable:
                fail(videoID: videoID, title: title, quality: quality, error: .requestedQualityUnavailable)
            }
        }
    }

    /// True while a transfer for this video+quality is live in the manager's
    /// observable task projection (progress events keep it populated).
    public func isInFlight(videoID: String, quality: DownloadQuality) -> Bool {
        downloadManager.liveTasks.contains {
            $0.videoID == videoID && $0.resolution == quality.rawValue
        }
    }

    public func acknowledgeFailure() {
        lastFailure = nil
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
        components: [DownloadComponent]
    ) async {
        let id = "\(videoID)-\(quality.rawValue)"
        let destination = destination(videoID: videoID, quality: quality)
        let request = DownloadRequest(
            id: id,
            videoID: videoID,
            resolution: resolution,
            destinationURL: destination,
            components: components
        )

        // MediaStream exposes no byte sizes today, so requiredBytes stays 0 and
        // the manager's storage admission check cannot pre-refuse; storage
        // failures surface through the task state instead.
        let enqueued = await downloadManager.enqueue(request)
        if enqueued.state.status == .failed {
            fail(videoID: videoID, title: title, quality: quality, error: enqueued.state.error ?? .storageRefused)
            return
        }

        await downloadManager.begin(request.id)

        guard let final = await downloadManager.waitForCompletion(request.id) else {
            fail(videoID: videoID, title: title, quality: quality, error: .interrupted)
            return
        }
        if final.state.status == .completed {
            let size = fileManager.size(of: destination)
            library.addDownloadedMedia(DownloadedMedia(
                id: id,
                videoID: videoID,
                title: title,
                resolution: quality.rawValue,
                fileURL: destination,
                sizeBytes: size,
                createdAt: Date()
            ))
        } else {
            fail(videoID: videoID, title: title, quality: quality, error: final.state.error ?? .unknown)
        }
    }

    private func destination(videoID: String, quality: DownloadQuality) -> URL {
        mediaDirectory
            .appendingPathComponent(videoID)
            .appendingPathComponent("\(quality.rawValue)")
            .appendingPathComponent("media.mp4")
    }
}
