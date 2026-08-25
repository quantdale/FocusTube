import Foundation
import SwiftData
import os
import FocusTubeCore

/// Single owner of the app's long-lived dependencies. Created once per app
/// process (held by `FocusTubeApp`'s `@State`) instead of inside `RootView`'s
/// init, which SwiftUI may evaluate repeatedly — discarded evaluations would
/// otherwise open extra ModelContainers and spawn duplicate reconciliation
/// work (HB-007).
///
/// Construction is centralized behind `make(launchArguments:)`: production gets
/// the real implementations; DEBUG UI-test launches get deterministic fakes
/// selected only by the `-focustube-ui-test` launch argument (compiled out of
/// Release builds entirely).
@MainActor
final class AppDependencies {
    let playerCoordinator: PlayerCoordinator
    let backgroundMedia: BackgroundMediaCoordinator
    let libraryStore: LibraryStore
    let downloadManager: DownloadManager
    let downloadService: DownloadService
    let homeStore: HomeFeedStore
    let searchStore: SearchStore
    let recentSearches: RecentSearchStore
    let auth: AuthSession
    let api: YouTubeAPI

    /// Process entry point used by `FocusTubeApp`.
    static func make(launchArguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        #if DEBUG
        if let scenario = UITestScenario.fromArguments(launchArguments) {
            return AppDependencies.fixture(scenario)
        }
        #endif
        return AppDependencies.production()
    }

    // MARK: - Production

    private static func production() -> AppDependencies {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self, DownloadRecord.self, RecentSearchEntry.self])
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
        excludeMediaFromBackups()
        return AppDependencies(
            auth: GoogleSignInAuthSession(),
            api: YouTubeDataClient(onItemsSkipped: Self.reportSkippedItems),
            extractor: YouTubeKitMediaExtractor(),
            transport: BackgroundDownloadTransport.shared,
            container: container,
            mediaDirectory: DownloadManager.defaultMediaDirectory(),
            incompleteDirectory: DownloadManager.defaultIncompleteDirectory(),
            validate: MediaAssetValidator.makeSeam()
        )
    }

    /// HB-016 non-silent requirement: partial page decodes report skipped-item
    /// counts through the platform logger at the composition boundary.
    private static func reportSkippedItems(endpoint: String, count: Int) {
        Logger(subsystem: "com.quantdale.FocusTube", category: "youtube-client")
            .warning("\(count, privacy: .public) malformed item(s) skipped in \(endpoint, privacy: .public)")
    }

    #if DEBUG
    // MARK: - UI-test fixture mode

    private static func fixture(_ scenario: UITestScenario) -> AppDependencies {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self, DownloadRecord.self, RecentSearchEntry.self])
        // The seeded-relaunch journey needs state that survives process exit;
        // every other scenario stays fully in-memory for isolation.
        let container: ModelContainer
        if scenario == .librarySeeded {
            let config = ModelConfiguration(schema: schema, url: FixtureLibrarySeeder.containerURL)
            container = (try? ModelContainer(for: schema, configurations: [config]))
                ?? (try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        } else {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [config])
        }

        let feedError: YouTubeAPIError?
        switch scenario {
        case .homeNetworkError: feedError = .network
        case .homeQuotaError: feedError = .quotaExceeded
        default: feedError = nil
        }
        let searchError: YouTubeAPIError? = scenario == .searchError ? .network : nil

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusTubeUITests-\(UUID().uuidString)")

        return AppDependencies(
            auth: FixtureAuthSession(authenticated: scenario != .signedOut),
            api: FixtureYouTubeAPI(feedError: feedError, searchError: searchError, searchHits: scenario != .searchEmpty),
            extractor: FixtureExtractor(),
            transport: ScriptedDownloadTransport(failsAfterProgress: scenario == .downloadFailure),
            container: container,
            mediaDirectory: scratch.appendingPathComponent("Media"),
            incompleteDirectory: scratch.appendingPathComponent("Incomplete"),
            storage: FixtureStorage(),
            // The scripted transport writes plain bytes; AVFoundation track
            // validation cannot pass on them (and must not run) in fixtures.
            validate: nil
        )
    }
    #endif

    // MARK: - Shared wiring

    private init(
        auth: AuthSession,
        api: YouTubeAPI,
        extractor: MediaExtracting,
        transport: DownloadTransport,
        container: ModelContainer,
        mediaDirectory: URL,
        incompleteDirectory: URL,
        storage: StorageProviding = VolumeStorage(),
        validate: (@Sendable (URL) async throws -> Void)?
    ) {
        self.auth = auth
        self.api = api
        let library = LibraryStore(context: ModelContext(container))
        let manager = DownloadManager(
            transport: transport,
            context: ModelContext(container),
            storage: storage,
            mediaDirectory: mediaDirectory,
            incompleteDirectory: incompleteDirectory,
            validate: validate
        )
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
        let player = PlayerCoordinator(extractor: extractor)
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
        let service = DownloadService(
            extractor: extractor,
            downloadManager: manager,
            library: library,
            mediaDirectory: mediaDirectory
        )
        self.downloadService = service
        // Terminal settlements outside DownloadService's own run loops —
        // reattached background transfers finishing after a relaunch, or
        // manager-level cancels — must still promote durable queued work.
        manager.onTaskSettled = { [weak service] _ in
            service?.downloadQueueDidSettle()
        }
        self.playerCoordinator = player
        self.backgroundMedia = media
        self.homeStore = HomeFeedStore(auth: auth, api: api)
        self.searchStore = SearchStore(auth: auth, api: api)
        self.recentSearches = RecentSearchStore(context: ModelContext(container))

        #if DEBUG
        if UITestScenario.fromArguments(ProcessInfo.processInfo.arguments) == .librarySeeded {
            FixtureLibrarySeeder.seedIfNeeded(library)
        }
        #endif
    }

    /// Best-effort: keeps downloaded media and staging areas out of iCloud/
    /// iTunes backups by marking the FocusTube Application-Support root. A
    /// failure (e.g. directory not created yet) is logged, never fatal.
    private static func excludeMediaFromBackups() {
        // `setResourceValues` is a mutating struct method, so the URL must be
        // addressable.
        var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
