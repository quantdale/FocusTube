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
        // tradeoff: library metadata then lasts only this session). The fallback
        // force-try cannot fail for disk reasons — in-memory storage does no I/O.
        let container: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Self.logger.fault("Persistent ModelContainer failed to open (\(error.localizedDescription, privacy: .public)); using in-memory store")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
        let library = LibraryStore(context: ModelContext(container))
        let manager = DownloadManager(transport: BackgroundDownloadTransport.shared, context: ModelContext(container))
        // Transfers that finish via the relaunched background session bypass
        // DownloadService; register them so offline media is never orphaned.
        // The library upserts by id, so this stays idempotent with in-app
        // registration.
        manager.onMediaFinalized = { [library] task in
            let size = (try? task.destinationURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            library.addDownloadedMedia(DownloadedMedia(
                id: task.id,
                videoID: task.videoID,
                title: task.videoID,
                resolution: task.resolution,
                fileURL: task.destinationURL,
                sizeBytes: Int64(size),
                createdAt: Date()
            ))
        }
        let player = PlayerCoordinator()
        let media = BackgroundMediaCoordinator(target: player)
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

    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "app-dependencies")
}
