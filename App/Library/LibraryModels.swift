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
    /// DDV2-08 additive presentation metadata (lightweight migration:
    /// legacy rows decode as nil and fall back gracefully in UI).
    var publishedAt: Date?
    var thumbnailURL: String?
    /// H3-03 (HB-029, additive): channel id + description so Library-origin
    /// navigation keeps Subscribe actions and the description. Legacy rows nil.
    var channelID: String?
    var videoDescription: String?

    init(videoID: String, title: String, channelTitle: String, lastPositionSeconds: Double, durationSeconds: Int?, updatedAt: Date, completed: Bool, publishedAt: Date? = nil, thumbnailURL: String? = nil, channelID: String? = nil, videoDescription: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
        self.lastPositionSeconds = lastPositionSeconds
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
        self.completed = completed
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.channelID = channelID
        self.videoDescription = videoDescription
    }
}

/// Persisted user save (watch-later style).
@Model
final class SavedItem {
    @Attribute(.unique) var videoID: String
    var title: String
    var channelTitle: String
    var savedAt: Date
    /// DDV2-08 additive presentation metadata.
    var durationSeconds: Int?
    var publishedAt: Date?
    var thumbnailURL: String?
    /// H3-03 (HB-029, additive): see WatchHistoryEntry.
    var channelID: String?
    var videoDescription: String?

    init(videoID: String, title: String, channelTitle: String, savedAt: Date, durationSeconds: Int? = nil, publishedAt: Date? = nil, thumbnailURL: String? = nil, channelID: String? = nil, videoDescription: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
        self.savedAt = savedAt
        self.durationSeconds = durationSeconds
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.channelID = channelID
        self.videoDescription = videoDescription
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
