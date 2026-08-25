import Foundation
import SwiftData
import os
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
    /// Presentation metadata captured at enqueue time so background-completed
    /// downloads can register in the library with a real title instead of the
    /// videoID placeholder. Additive optionals: legacy rows decode as nil
    /// (lightweight migration), and nil falls back to `videoID` at lookup.
    var title: String?
    var channelTitle: String?
    /// Durable queue payload (DDV2-01): planning metadata for a
    /// capacity-deferred `.queued` record so promotion can be reconstructed
    /// after process death. Additive optional — legacy rows decode as nil and
    /// are synthesized from the row's own fields at restore. Deliberately
    /// carries no media URLs; queued rows persist empty components.
    var queuedMetadataData: Data?
    /// HB-023 (additive, lightweight migration): the duration captured at
    /// enqueue time so failed-row RETRIES re-run storage admission truthfully
    /// instead of estimating zero and skipping the free-space pre-check.
    /// Legacy rows read nil; retry then keeps the historical unknown-duration
    /// behavior.
    var plannedDurationSeconds: Double?

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

    /// Degrades to an empty list on an undecodable payload (e.g. schema drift
    /// after an app update), but logs the failure instead of swallowing it.
    /// The payload itself is never logged — component JSON contains source URLs.
    var components: [DownloadComponent] {
        do {
            return try JSONDecoder().decode([DownloadComponent].self, from: componentsData)
        } catch {
            Self.logger.error("Components decode failed (\(error.localizedDescription)); treating as empty")
            return []
        }
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

    /// Stores user-facing presentation metadata; status/progress fields are
    /// untouched so state-machine events can never clobber it.
    func applyPresentationMetadata(title: String, channelTitle: String) {
        self.title = title
        self.channelTitle = channelTitle
    }



    /// Decodes the durable queue payload; nil when absent (legacy row) or
    /// undecodable (schema drift). The failure is logged, never fatal — the
    /// restore path synthesizes an equivalent payload from the row fields.
    var queuedMetadata: QueuedDownloadMetadata? {
        guard let data = queuedMetadataData else { return nil }
        do {
            return try JSONDecoder().decode(QueuedDownloadMetadata.self, from: data)
        } catch {
            Self.logger.error("Queued metadata decode failed (\(error.localizedDescription)); treating as legacy")
            return nil
        }
    }

    func applyQueuedMetadata(_ metadata: QueuedDownloadMetadata) {
        self.queuedMetadataData = try? JSONEncoder().encode(metadata)
    }

    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "download-record")
}
