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
    /// Injected persistence boundary (H3-03/HB-025): production performs
    /// `context.save()`; deterministic failure-injection tests substitute a
    /// throwing closure.
    private let performSave: () throws -> Void
    /// HB-025 truthful signal: set when a SwiftData save fails, cleared by the
    /// next successful save. UI may surface this as a degraded-persistence
    /// indicator instead of silently claiming durability.
    public private(set) var isPersistenceDegraded = false

    public init(
        context: ModelContext,
        fileManager: FileManaging = FileManager.default,
        saveHandler: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.fileManager = fileManager
        self.performSave = saveHandler ?? { try context.save() }
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
        thumbnailURL: String? = nil,
        channelID: String? = nil,
        videoDescription: String? = nil
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
            if let channelID { existing.channelID = channelID }
            if let videoDescription { existing.videoDescription = videoDescription }
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
                thumbnailURL: thumbnailURL,
                channelID: channelID,
                videoDescription: videoDescription
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

    /// HB-027 render-path fix: ONE full-history fetch per mutation generation,
    /// projected to a videoID→resume-fraction map that card rows index in O(1).
    /// Previously every visible VideoCard triggered its own complete-table
    /// fetch per body evaluation (N rows ⇒ N scans per render, re-run on every
    /// progress tick). Memoized against the mutation `revision`, so playback
    /// progress invalidation costs at most one fetch per surface per tick.
    public func resumeFractions() -> [String: Double] {
        if fractionProjectionRevision == revision { return fractionProjection }
        var map: [String: Double] = [:]
        for entry in history {
            guard !entry.completed,
                  let duration = entry.durationSeconds, duration > 0 else { continue }
            map[entry.videoID] = min(max(entry.lastPositionSeconds / Double(duration), 0), 1)
        }
        fractionProjection = map
        fractionProjectionRevision = revision
        return map
    }

    private var fractionProjection: [String: Double] = [:]
    private var fractionProjectionRevision = -1

    /// Render-path snapshot for the Library surface: ONE full-history fetch per
    /// mutation generation, shared by every section that reads history. The
    /// continue-watching and recent-history sections previously each triggered
    /// their own complete-table SwiftData fetch on EVERY body evaluation; with
    /// this memoization a re-render costs at most one fetch per mutation
    /// revision and section filtering runs over the in-memory array.
    public func historySnapshot() -> [WatchHistoryEntry] {
        _ = revision
        if historySnapshotRevision == revision { return historySnapshotCache }
        historySnapshotCache = history
        historySnapshotRevision = revision
        return historySnapshotCache
    }

    private var historySnapshotCache: [WatchHistoryEntry] = []
    private var historySnapshotRevision = -1

    /// Same one-fetch-per-revision contract as `historySnapshot()`, for the
    /// Saved section which previously fetched the full table twice per body
    /// evaluation (once for the empty check, once for the rows).
    public func savedSnapshot() -> [SavedItem] {
        _ = revision
        if savedSnapshotRevision == revision { return savedSnapshotCache }
        savedSnapshotCache = saved
        savedSnapshotRevision = revision
        return savedSnapshotCache
    }

    private var savedSnapshotCache: [SavedItem] = []
    private var savedSnapshotRevision = -1

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
        thumbnailURL: String? = nil,
        channelID: String? = nil,
        videoDescription: String? = nil
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
            if let channelID { existing.channelID = channelID }
            if let videoDescription { existing.videoDescription = videoDescription }
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
                thumbnailURL: thumbnailURL,
                channelID: channelID,
                videoDescription: videoDescription
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
            let previousTitle = existing.title
            let previousChannelTitle = existing.channelTitle
            let previousResolution = existing.resolution
            let previousFileURL = existing.fileURL
            let previousSizeBytes = existing.sizeBytes
            let previousCreatedAt = existing.createdAt
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
            mutate()
            if !save() {
                // HB-025 durability-critical rollback: the offline index must
                // never advertise a download whose durable row failed to
                // persist. Restore the exact prior field values.
                existing.title = previousTitle
                existing.channelTitle = previousChannelTitle
                existing.resolution = previousResolution
                existing.fileURL = previousFileURL
                existing.sizeBytes = previousSizeBytes
                existing.createdAt = previousCreatedAt
                Self.logger.fault("Downloaded-index upsert rolled back after failed save")
            }
        } else {
            context.insert(media)
            mutate()
            if !save() {
                context.delete(media)
                Self.logger.fault("Downloaded-index insert rolled back after failed save")
            }
        }
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

    /// Store-filtered point lookups. Every one of these runs on warm paths
    /// (playback progress ticks every 5 s, video-page opens, per-row metadata
    /// reads), so each fetches only the matching row instead of materializing
    /// the whole table and scanning it in memory.
    private func historyEntryOrThrow(_ videoID: String) throws -> WatchHistoryEntry? {
        var descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func savedItemOrThrow(_ videoID: String) throws -> SavedItem? {
        var descriptor = FetchDescriptor<SavedItem>(
            predicate: #Predicate { $0.videoID == videoID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func downloadedEntryOrThrow(_ id: String) throws -> DownloadedMedia? {
        var descriptor = FetchDescriptor<DownloadedMedia>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Persistence / filesystem hygiene

    /// Persists pending changes. On failure the store flags itself degraded
    /// (observable) and logs loudly; callers that need durable truth roll
    /// their optimistic mutation back (see `addDownloadedMedia`).
    @discardableResult
    private func save() -> Bool {
        do {
            try performSave()
            isPersistenceDegraded = false
            return true
        } catch {
            isPersistenceDegraded = true
            Self.logger.fault("SwiftData save failed (\(error.localizedDescription)); persistence degraded")
            return false
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
