import Foundation
import FocusTubeCore

/// Orchestrates a real download: resolves media, selects the stream for the
/// chosen quality, drives `DownloadManager`, and on completion registers the
/// finalized file in the `LibraryStore` so it appears offline in the Downloads
/// tab. The loop is: pick → download → finalize → register.
@MainActor
public final class DownloadService {
    private let extractor: MediaExtracting
    private let downloadManager: DownloadManager
    private let library: LibraryStore
    private let picker = DownloadQualityPicker()
    private let fileManager: FileManaging

    public init(
        extractor: MediaExtracting = YouTubeKitMediaExtractor(),
        downloadManager: DownloadManager,
        library: LibraryStore,
        fileManager: FileManaging = FileManager.default
    ) {
        self.extractor = extractor
        self.downloadManager = downloadManager
        self.library = library
        self.fileManager = fileManager
    }

    public func download(videoID: String, title: String, channelTitle: String, quality: DownloadQuality) async {
        do {
            let media = try await extractor.resolve(videoID: videoID)
            guard let stream = selectStream(media: media, quality: quality) else { return }
            let destination = defaultDestination(videoID: videoID, quality: quality)
            let request = DownloadRequest(
                id: "\(videoID)-\(quality.rawValue)",
                videoID: videoID,
                streamID: stream.id,
                resolution: quality.rawValue,
                sourceURL: stream.sourceURL,
                destinationURL: destination
            )
            _ = await downloadManager.enqueue(request)
            await downloadManager.begin(request.id)

            for _ in 0..<180 {
                if let task = await downloadManager.records.first(where: { $0.id == request.id }) {
                    if task.state.status == .completed {
                        let size = fileManager.size(of: destination)
                        library.addDownloadedMedia(DownloadedMedia(
                            id: request.id,
                            videoID: videoID,
                            title: title,
                            resolution: quality.rawValue,
                            fileURL: destination,
                            sizeBytes: size,
                            createdAt: Date()
                        ))
                        return
                    }
                    if task.state.status == .failed { return }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            return
        }
    }

    private func selectStream(media: ResolvedMedia, quality: DownloadQuality) -> MediaStream? {
        let combined = MediaStreamFilter.allowed(media.combined)
            .filter { $0.nativePlayable && $0.resolution == quality.rawValue }
        if let exact = combined.first { return exact }
        return combined.max { ($0.resolution ?? 0) < ($1.resolution ?? 0) }
    }

    private func defaultDestination(videoID: String, quality: DownloadQuality) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FocusTubeDownloads")
        return dir.appendingPathComponent("\(videoID)-\(quality.rawValue).mp4")
    }
}
