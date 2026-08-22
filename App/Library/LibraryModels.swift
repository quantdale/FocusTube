import Foundation
import SwiftData
import FocusTubeCore

/// Persisted watch-history / resume-position entry.
@Model
final class WatchHistoryEntry {
    @Attribute(.unique) var videoID: String
    var title: String
    var channelTitle: String
    var lastPositionSeconds: Double
    var durationSeconds: Int?
    var updatedAt: Date
    var completed: Bool

    init(videoID: String, title: String, channelTitle: String, lastPositionSeconds: Double, durationSeconds: Int?, updatedAt: Date, completed: Bool) {
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
        self.completed = completed
    }
}

/// Persisted user save (watch-later style).
@Model
final class SavedItem {
    @Attribute(.unique) var videoID: String
    var title: String
    var channelTitle: String
    var savedAt: Date

    init(videoID: String, title: String, channelTitle: String, savedAt: Date) {
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
        self.savedAt = savedAt
    }
}

/// Index of a finalized offline media file. Reconciled against the filesystem.
@Model
final class DownloadedMedia {
    @Attribute(.unique) var id: String
    var videoID: String
    var title: String
    var resolution: Int
    var fileURL: URL
    var sizeBytes: Int64
    var createdAt: Date
    /// Additive optional (lightweight migration: legacy rows decode as nil).
    var channelTitle: String?

    init(id: String, videoID: String, title: String, resolution: Int, fileURL: URL, sizeBytes: Int64, createdAt: Date, channelTitle: String? = nil) {
        self.id = id
        self.videoID = videoID
        self.title = title
        self.resolution = resolution
        self.fileURL = fileURL
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.channelTitle = channelTitle
    }
}
