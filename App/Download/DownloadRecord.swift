import Foundation
import SwiftData
import FocusTubeCore

/// SwiftData-persisted download record. Mirrors the deterministic `DownloadTask`
/// so metadata survives relaunch and reconciles with filesystem reality. The
/// component list is persisted so an interrupted download can be retried after a
/// process relaunch even though the in-memory coordinator state is gone.
@Model
final class DownloadRecord {
    @Attribute(.unique) var id: String
    var videoID: String
    var resolution: Int
    var destinationURL: URL
    var statusRaw: String
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var errorRaw: String?
    var createdAt: Date
    var componentsData: Data

    init(task: DownloadTask) {
        self.id = task.id
        self.videoID = task.videoID
        self.resolution = task.resolution
        self.destinationURL = task.destinationURL
        self.statusRaw = task.state.status.rawValue
        self.bytesDownloaded = task.state.bytesDownloaded
        self.totalBytes = task.state.totalBytes
        self.errorRaw = task.state.error?.rawValue
        self.createdAt = Date()
        self.componentsData = (try? JSONEncoder().encode(task.components)) ?? Data()
    }

    var components: [DownloadComponent] {
        (try? JSONDecoder().decode([DownloadComponent].self, from: componentsData)) ?? []
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
            resolution: resolution,
            destinationURL: destinationURL,
            components: components,
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
