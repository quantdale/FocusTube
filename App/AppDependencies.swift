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
    let localLibrary: LocalLibraryModel

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
            localLibrary: LocalLibraryModel(http: URLSessionHTTP(), fileURL: LocalLibraryModel.defaultFileURL()),
            makePlayer: { PlayerCoordinator(engine: WKWebViewPlayerEngine()) },
            container: container
        )
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

        return AppDependencies(
            localLibrary: LocalLibraryModel(
                http: FixtureHTTP(feedFails: scenario == .homeNetworkError),
                fileURL: FixtureLocalLibrary.fileURL(for: scenario)
            ),
            makePlayer: {
                PlayerCoordinator(engine: FixturePlayerEngine(), resolveID: FixturePlayerEngine.resolveFixtureID)
            },
            container: container
        )
    }
    #endif

    // MARK: - Shared wiring

    private init(
        localLibrary: LocalLibraryModel,
        makePlayer: () -> PlayerCoordinator,
        container: ModelContainer
    ) {
        self.localLibrary = localLibrary
        let library = LibraryStore(context: ModelContext(container))
        let player = makePlayer()
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
        self.playerCoordinator = player
        self.backgroundMedia = media

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
