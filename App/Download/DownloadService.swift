import Foundation
import FocusTubeCore

/// Orchestrates a real download: resolves media, selects the exact download
/// strategy for the chosen quality (combined, or adaptive video+audio mux),
/// drives `DownloadManager` over a durable background `URLSession`, and on
/// completion registers the finalized file in the `LibraryStore` so it appears
/// offline in the Downloads tab. The loop is: plan -> download -> finalize ->
/// register. No quality is ever silently downgraded.
@MainActor
public final class DownloadService {
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
        case .unavailable:
            // The quality picker only offers qualities the planner can satisfy,
            // so this is defensive. No silent downgrade is performed.
            return
        }
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

        let enqueued = await downloadManager.enqueue(request)
        if enqueued.state.status == .failed {
            return
        }

        await downloadManager.begin(request.id)

        guard let final = await downloadManager.waitForCompletion(request.id) else { return }
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
        }
    }

    private func destination(videoID: String, quality: DownloadQuality) -> URL {
        mediaDirectory
            .appendingPathComponent(videoID)
            .appendingPathComponent("\(quality.rawValue)")
            .appendingPathComponent("media.mp4")
    }
}
