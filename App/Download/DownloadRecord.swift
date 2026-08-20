import Foundation
import SwiftData
import FocusTubeCore

/// SwiftData-persisted download record. Mirrors the deterministic `DownloadTask`
/// so metadata survives relaunch and reconciles with filesystem reality.
@Model
final class DownloadRecord {
    @Attribute(.unique) var id: String
    var videoID: String
    var streamID: String
    var resolution: Int
    var sourceURL: URL
    var destinationURL: URL
    var statusRaw: String
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var errorRaw: String?
    var createdAt: Date

    init(task: DownloadTask) {
        self.id = task.id
        self.videoID = task.videoID
        self.streamID = task.streamID
        self.resolution = task.resolution
        self.sourceURL = task.sourceURL
        self.destinationURL = task.destinationURL
        self.statusRaw = task.state.status.rawValue
        self.bytesDownloaded = task.state.bytesDownloaded
        self.totalBytes = task.state.totalBytes
        self.errorRaw = task.state.error?.rawValue
        self.createdAt = Date()
    }

    var downloadTask: DownloadTask {
        let status = DownloadStatus(rawValue: statusRaw) ?? .failed
        let error = errorRaw.flatMap { DownloadError(rawValue: $0) }
        var state = DownloadState(status: status)
        state.error = error
        state.bytesDownloaded = bytesDownloaded
        state.totalBytes = totalBytes
        return DownloadTask(
            id: id,
            videoID: videoID,
            streamID: streamID,
            resolution: resolution,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            state: state
        )
    }

    func apply(_ task: DownloadTask) {
        self.statusRaw = task.state.status.rawValue
        self.errorRaw = task.state.error?.rawValue
        self.bytesDownloaded = task.state.bytesDownloaded
        self.totalBytes = task.state.totalBytes
    }
}
