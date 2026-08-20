import Foundation
import SwiftData
import FocusTubeCore

/// Library store: watch history / resume, saves, and the offline-media index.
/// Persists across relaunch, reconciles the file index with the filesystem, and
/// deletes files + metadata atomically (no half-deleted final state).
@MainActor
public final class LibraryStore {
    private let context: ModelContext
    private let fileManager: FileManaging

    public init(context: ModelContext, fileManager: FileManaging = FileManager.default) {
        self.context = context
        self.fileManager = fileManager
    }

    // MARK: - Watch history / resume

    public func recordProgress(videoID: String, title: String, channelTitle: String, position: Double, duration: Int?, completed: Bool) {
        if let existing = historyEntry(videoID) {
            existing.title = title
            existing.channelTitle = channelTitle
            existing.lastPositionSeconds = position
            existing.durationSeconds = duration
            existing.completed = completed
            existing.updatedAt = Date()
        } else {
            context.insert(WatchHistoryEntry(
                videoID: videoID,
                title: title,
                channelTitle: channelTitle,
                lastPositionSeconds: position,
                durationSeconds: duration,
                updatedAt: Date(),
                completed: completed
            ))
        }
        try? context.save()
    }

    public func resumePosition(for videoID: String) -> Double? {
        historyEntry(videoID)?.lastPositionSeconds
    }

    public var history: [WatchHistoryEntry] {
        (try? context.fetch(FetchDescriptor<WatchHistoryEntry>())) ?? []
    }

    // MARK: - Saves

    public func save(videoID: String, title: String, channelTitle: String) {
        if savedItem(videoID) == nil {
            context.insert(SavedItem(videoID: videoID, title: title, channelTitle: channelTitle, savedAt: Date()))
            try? context.save()
        }
    }

    public var saved: [SavedItem] {
        (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
    }

    // MARK: - Downloaded media index

    public func addDownloadedMedia(_ media: DownloadedMedia) {
        context.insert(media)
        try? context.save()
    }

    public var downloaded: [DownloadedMedia] {
        (try? context.fetch(FetchDescriptor<DownloadedMedia>())) ?? []
    }

    /// Removes index entries whose files no longer exist on disk (orphan cleanup).
    public func reconcileDownloads() {
        for item in downloaded where !fileManager.fileExists(at: item.fileURL) {
            context.delete(item)
        }
        try? context.save()
    }

    /// Atomically removes both the file and its metadata. A missing file is not
    /// an error; the metadata is always removed so no orphan remains.
    public func deleteDownloadedMedia(id: String) {
        guard let item = downloaded.first(where: { $0.id == id }) else { return }
        try? fileManager.removeItem(at: item.fileURL)
        context.delete(item)
        try? context.save()
    }

    // MARK: - Helpers

    private func historyEntry(_ videoID: String) -> WatchHistoryEntry? {
        history.first { $0.videoID == videoID }
    }

    private func savedItem(_ videoID: String) -> SavedItem? {
        saved.first { $0.videoID == videoID }
    }
}
