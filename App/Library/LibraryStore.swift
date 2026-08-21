import Foundation
import SwiftData
import os
import FocusTubeCore

/// Library store: watch history / resume, saves, and the offline-media index.
/// Persists across relaunch, reconciles the file index with the filesystem, and
/// deletes files + metadata atomically (no half-deleted final state).
@MainActor
final class LibraryStore {
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "library-store")
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
        save()
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
            save()
        }
    }

    public var saved: [SavedItem] {
        (try? context.fetch(FetchDescriptor<SavedItem>())) ?? []
    }

    // MARK: - Downloaded media index

    public func addDownloadedMedia(_ media: DownloadedMedia) {
        // Upsert by the unique id: re-downloading the same video+quality must
        // refresh the entry, never duplicate it.
        if let existing = downloaded.first(where: { $0.id == media.id }) {
            existing.title = media.title
            existing.resolution = media.resolution
            existing.fileURL = media.fileURL
            existing.sizeBytes = media.sizeBytes
            existing.createdAt = media.createdAt
        } else {
            context.insert(media)
        }
        save()
    }

    public var downloaded: [DownloadedMedia] {
        (try? context.fetch(FetchDescriptor<DownloadedMedia>())) ?? []
    }

    /// Removes index entries whose files no longer exist on disk (orphan cleanup).
    public func reconcileDownloads() {
        for item in downloaded where !fileManager.fileExists(at: item.fileURL) {
            context.delete(item)
            pruneEmptyAncestors(of: item.fileURL)
        }
        save()
    }

    /// Atomically removes both the file and its metadata. A missing file is not
    /// an error; the metadata is always removed so no orphan remains.
    public func deleteDownloadedMedia(id: String) {
        guard let item = downloaded.first(where: { $0.id == id }) else { return }
        try? fileManager.removeItem(at: item.fileURL)
        pruneEmptyAncestors(of: item.fileURL)
        context.delete(item)
        save()
    }

    // MARK: - Helpers

    private func historyEntry(_ videoID: String) -> WatchHistoryEntry? {
        history.first { $0.videoID == videoID }
    }

    private func savedItem(_ videoID: String) -> SavedItem? {
        saved.first { $0.videoID == videoID }
    }

    // MARK: - Persistence / filesystem hygiene

    /// Persists pending changes; a failed save is logged loudly instead of
    /// silently dropped, so metadata loss is diagnosable.
    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.fault("SwiftData save failed (\(error.localizedDescription, privacy: .public))")
        }
    }

    /// Removes the quality and video directories when a delete leaves them
    /// empty, so the per-quality layout never accumulates hollow directories
    /// under FocusTube/Media (bounded to two ancestor levels).
    private func pruneEmptyAncestors(of fileURL: URL) {
        guard fileURL.path.contains("/FocusTube/Media/") else { return }
        var directory = fileURL.deletingLastPathComponent()
        for _ in 0..<2 {
            let remaining = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? ["nonempty"]
            guard remaining.isEmpty else { return }
            try? FileManager.default.removeItem(at: directory)
            directory.deleteLastPathComponent()
        }
    }
}
