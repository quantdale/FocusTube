import Foundation
import SwiftData
import os
import FocusTubeCore

/// Single owner of the app's long-lived dependencies. Created once per app
/// process (held by `FocusTubeApp`'s `@State`) instead of inside `RootView`'s
/// init, which SwiftUI may evaluate repeatedly — discarded evaluations would
/// otherwise open extra ModelContainers and spawn duplicate reconciliation
/// work (HB-007).
@MainActor
final class AppDependencies {
    let playerCoordinator: PlayerCoordinator
    let backgroundMedia: BackgroundMediaCoordinator
    let libraryStore: LibraryStore
    let downloadManager: DownloadManager
    let downloadService: DownloadService

    init() {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self, DownloadRecord.self])
        // Resilience over durability: a corrupted/unopenable store must not crash
        // the app at launch, so fall back to an in-memory container (personal-use
        // tradeoff: library metadata then lasts only this session). In-memory
        // storage does no I/O, so if even that fallback fails the model itself is
        // unusable and aborting with context is the deliberate last resort.
        let container: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Self.logger.fault("Persistent ModelContainer failed to open (\(error.localizedDescription)); using in-memory store")
            do {
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [memoryConfig])
            } catch let memoryError {
                fatalError("In-memory ModelContainer fallback failed: \(memoryError)")
            }
        }
        let library = LibraryStore(context: ModelContext(container))
        let manager = DownloadManager(transport: BackgroundDownloadTransport.shared, context: ModelContext(container))
        Self.excludeMediaFromBackups()
        // Transfers that finish via the relaunched background session bypass
        // DownloadService; register them so offline media is never orphaned.
        // The library upserts by id, so this stays idempotent with in-app
        // registration. Presentation metadata captured at enqueue time provides
        // the real title; legacy/missing metadata falls back to the videoID
        // (the library upsert never downgrades an existing real title).
        manager.onMediaFinalized = { [library, manager] task in
            let metadata = manager.presentationMetadata(taskID: task.id)
            let size = (try? task.destinationURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            library.addDownloadedMedia(DownloadedMedia(
                id: task.id,
                videoID: task.videoID,
                title: metadata?.title ?? task.videoID,
                resolution: task.resolution,
                fileURL: task.destinationURL,
                sizeBytes: Int64(size),
                createdAt: Date(),
                channelTitle: metadata?.channelTitle
            ))
        }
        let player = PlayerCoordinator()
        let media = BackgroundMediaCoordinator(target: player)
        // Interruption auto-resume must respect user intent: capture whether
        // playback was actually running when the interruption began.
        media.isPlayingProvider = { [weak player] in
            guard let player else { return false }
            return player.state.status == .playing
        }
        // Republish lock-screen metadata whenever playback state or progress
        // changes; the coordinator owns the snapshot, the media coordinator
        // owns MPNowPlayingInfoCenter.
        player.onNowPlayingChanged = { [weak player, weak media] in
            guard let player, let media else { return }
            media.publishNowPlaying(snapshot: player.nowPlayingSnapshot)
        }

        self.libraryStore = library
        self.downloadManager = manager
        self.downloadService = DownloadService(downloadManager: manager, library: library)
        self.playerCoordinator = player
        self.backgroundMedia = media
    }

    /// Best-effort: keeps downloaded media and staging areas out of iCloud/
    /// iTunes backups by marking the FocusTube Application-Support root. A
    /// failure (e.g. directory not created yet) is logged, never fatal.
    private static func excludeMediaFromBackups() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusTube")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            // `resourceValues` is read-only; writing goes through setResourceValues.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try root.setResourceValues(values)
        } catch {
            Self.logger.error("Backup exclusion not applied (\(error.localizedDescription))")
        }
    }

    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "app-dependencies")
}
