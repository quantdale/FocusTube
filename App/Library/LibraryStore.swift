import Foundation
import Observation
import SwiftData
import os
import FocusTubeCore

/// Library store: watch history / resume, saves, and the offline-media index.
/// Persists across relaunch, reconciles the file index with the filesystem, and
/// deletes files + metadata atomically (no half-deleted final state).
///
/// `@Observable` with an explicit revision counter: the public collections are
/// computed SwiftData fetches, so WITHOUT a tracked stored dependency mutated
/// by every write, SwiftUI views rendering these lists would never invalidate
/// on mid-session changes (e.g. a finished download registering while the
/// Downloads tab is frontmost).
@MainActor
@Observable
final class LibraryStore {
    /// Bumped by every mutation; read by every collection getter so the
    /// observation machinery ties list reads to write invalidation.
    private var revision = 0

    private func mutate() { revision &+= 1 }
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "library-store")
    private let context: ModelContext
    private let fileManager: FileManaging

    public init(context: ModelContext, fileManager: FileManaging = FileManager.default) {
        self.context = context
        self.fileManager = fileManager
    }

    // MARK: - Watch history / resume

    public func recordProgress(
        videoID: String,
        title: String,
        channelTitle: String,
        position: Double,
        duration: Int?,
        completed: Bool,
        publishedAt: Date? = nil,
        thumbnailURL: String? = nil
    ) {
        // A failed fetch must not silently insert a duplicate entry for a
        // video that may already have history — abort and log instead.
        let existing: WatchHistoryEntry?
        do {
            existing = try historyEntryOrThrow(videoID)
        } catch {
            Self.logger.fault("History fetch failed (\(error.localizedDescription)); aborting progress update")
            return
        }
        if let existing {
            existing.title = title
            existing.channelTitle = channelTitle
            existing.lastPositionSeconds = position
            existing.durationSeconds = duration ?? existing.durationSeconds
            existing.completed = completed
            existing.updatedAt = Date()
            if let publishedAt { existing.publishedAt = publishedAt }
            if let thumbnailURL { existing.thumbnailURL = thumbnailURL }
        } else {
            context.insert(WatchHistoryEntry(
                videoID: videoID,
                title: title,
                channelTitle: channelTitle,
                lastPositionSeconds: position,
                durationSeconds: duration,
                updatedAt: Date(),
                completed: completed,
                publishedAt: publishedAt,
                thumbnailURL: thumbnailURL
            ))
        }
        mutate()
        save()
    }

    public func resumePosition(for videoID: String) -> Double? {
        do {
            return try historyEntryOrThrow(videoID)?.lastPositionSeconds
        } catch {
            Self.logger.error("History fetch failed (\(error.localizedDescription)); no resume position")
            return nil
        }
    }

    public var history: [WatchHistoryEntry] {
        _ = revision
        do {
            // Most-recent-first so "Continue watching" reads chronologically.
            let descriptor = FetchDescriptor<WatchHistoryEntry>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("History fetch failed (\(error.localizedDescription)); displaying empty")
            return []
        }
    }

    /// Removes one history entry. A missing entry or failed fetch is a no-op.
    public func removeHistory(videoID: String) {
        guard case let entry? = (try? historyEntryOrThrow(videoID)) else { return }
        context.delete(entry)
        mutate()
        save()
    }

    // MARK: - Saves

    public func save(
        videoID: String,
        title: String,
        channelTitle: String,
        durationSeconds: Int? = nil,
        publishedAt: Date? = nil,
        thumbnailURL: String? = nil
    ) {
        // A failed fetch must not silently insert a duplicate save — abort.
        let existing: SavedItem?
        do {
            existing = try savedItemOrThrow(videoID)
        } catch {
            Self.logger.fault("Saved-item fetch failed (\(error.localizedDescription)); aborting save")
            return
        }
        if let existing {
            existing.durationSeconds = durationSeconds ?? existing.durationSeconds
            if let publishedAt { existing.publishedAt = publishedAt }
            if let thumbnailURL { existing.thumbnailURL = thumbnailURL }
            mutate()
            save()
        } else {
            context.insert(SavedItem(
                videoID: videoID,
                title: title,
                channelTitle: channelTitle,
                savedAt: Date(),
                durationSeconds: durationSeconds,
                publishedAt: publishedAt,
                thumbnailURL: thumbnailURL
            ))
            mutate()
            save()
        }
    }

    /// True when the video currently has a saved entry.
    public func isSaved(videoID: String) -> Bool {
        guard let item = try? savedItemOrThrow(videoID) else { return false }
        return item != nil
    }

    /// Removes a saved entry. A missing entry or failed fetch is a no-op.
    public func removeSaved(videoID: String) {
        guard case let existing? = (try? savedItemOrThrow(videoID)) else { return }
        context.delete(existing)
        mutate()
        save()
    }

    public var saved: [SavedItem] {
        _ = revision
        do {
            let descriptor = FetchDescriptor<SavedItem>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Saved list fetch failed (\(error.localizedDescription)); displaying empty")
            return []
        }
    }

    // MARK: - Downloaded media index

    public func addDownloadedMedia(_ media: DownloadedMedia) {
        // Upsert by the unique id: re-downloading the same video+quality must
        // refresh the entry, never duplicate it. A failed fetch aborts the
        // upsert rather than risking a duplicate row.
        let existing: DownloadedMedia?
        do {
            existing = try downloadedEntryOrThrow(media.id)
        } catch {
            Self.logger.fault("Downloaded-index fetch failed (\(error.localizedDescription)); aborting library upsert")
            return
        }
        if let existing {
            // Never downgrade real presentation metadata: background
            // completion may register with only the videoID, and the failed-
            // download retry path may carry an empty channel title. Absent or
            // blank must never clobber a known value.
            let newIsPlaceholder = media.title == media.videoID
            let existingIsPlaceholder = existing.title == existing.videoID
            if !newIsPlaceholder || existingIsPlaceholder {
                existing.title = media.title
            }
            if let channelTitle = media.channelTitle, !channelTitle.isEmpty {
                existing.channelTitle = channelTitle
            }
            existing.resolution = media.resolution
            existing.fileURL = media.fileURL
            existing.sizeBytes = media.sizeBytes
            existing.createdAt = media.createdAt
        } else {
            context.insert(media)
        }
        mutate()
        save()
    }

    public var downloaded: [DownloadedMedia] {
        _ = revision
        do {
            let descriptor = FetchDescriptor<DownloadedMedia>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("Downloaded index fetch failed (\(error.localizedDescription)); displaying empty")
            return []
        }
    }

    /// Removes index entries whose files no longer exist on disk (orphan cleanup).
    public func reconcileDownloads() {
        var removedAny = false
        for item in downloaded where !fileManager.fileExists(at: item.fileURL) {
            context.delete(item)
            pruneEmptyAncestors(of: item.fileURL)
            removedAny = true
        }
        if removedAny { mutate() }
        save()
    }

    /// Atomically removes both the file and its metadata. A missing file is not
    /// an error; the metadata is still removed so no orphan remains. Any other
    /// removal failure keeps the metadata row so the entry stays deletable and
    /// diagnosable instead of silently orphaning the file.
    public func deleteDownloadedMedia(id: String) {
        let existing: DownloadedMedia?
        do {
            existing = try downloadedEntryOrThrow(id)
        } catch {
            Self.logger.fault("Downloaded-index fetch failed (\(error.localizedDescription)); aborting delete")
            return
        }
        guard let item = existing else { return }
        do {
            try fileManager.removeItem(at: item.fileURL)
        } catch let error as NSError {
            let isFileNotFound =
                error.domain == NSCocoaErrorDomain
                && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError)
            guard isFileNotFound else {
                Self.logger.fault("Final-media removal failed (\(error.localizedDescription)); keeping library entry")
                return
            }
        }
        pruneEmptyAncestors(of: item.fileURL)
        context.delete(item)
        mutate()
        save()
    }

    // MARK: - Helpers

    private func historyEntryOrThrow(_ videoID: String) throws -> WatchHistoryEntry? {
        try context.fetch(FetchDescriptor<WatchHistoryEntry>()).first { $0.videoID == videoID }
    }

    private func savedItemOrThrow(_ videoID: String) throws -> SavedItem? {
        try context.fetch(FetchDescriptor<SavedItem>()).first { $0.videoID == videoID }
    }

    private func downloadedEntryOrThrow(_ id: String) throws -> DownloadedMedia? {
        try context.fetch(FetchDescriptor<DownloadedMedia>()).first { $0.id == id }
    }

    // MARK: - Persistence / filesystem hygiene

    /// Persists pending changes; a failed save is logged loudly instead of
    /// silently dropped, so metadata loss is diagnosable.
    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.fault("SwiftData save failed (\(error.localizedDescription))")
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
