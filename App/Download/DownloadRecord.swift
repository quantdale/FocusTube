import Foundation
import SwiftData

/// Legacy SwiftData download record (ADR-0007 removed downloads). Kept only so
/// existing on-device stores keep opening with the same schema; nothing writes
/// it anymore. Remove together with `DownloadedMedia` in a migration PR.
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

    init(id: String, videoID: String, resolution: Int, destinationURL: URL, statusRaw: String) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.destinationURL = destinationURL
        self.statusRaw = statusRaw
        self.bytesDownloaded = 0
        self.totalBytes = 0
        self.createdAt = Date()
        self.componentsData = Data()
    }
}
