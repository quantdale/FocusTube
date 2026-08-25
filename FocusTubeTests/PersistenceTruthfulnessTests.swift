import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// H3-03 / HB-025: truthful SwiftData persistence semantics.
///
/// Durability-critical data (the offline download index) rolls back its
/// optimistic mutation when the save fails, so the session never advertises a
/// download whose durable row vanished. Session-tolerant data (history, saves)
/// keeps its in-memory state for usability but flips an observable degraded
/// flag instead of silently claiming durability. Recents commit write-through:
/// the visible list only advances after persistence succeeds.
@MainActor
final class PersistenceTruthfulnessTests: XCTestCase {
    /// Switchable save seam: fails until released; can be re-armed.
    private final class SwitchableSaver: @unchecked Sendable {
        private let lock = NSLock()
        private var failing = true

        func release() { lock.withLock { failing = false } }
        func rearm() { lock.withLock { failing = true } }

        func perform() throws {
            if lock.withLock({ failing }) {
                throw NSError(domain: "test", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "injected save failure"])
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func downloadedMedia(id: String, title: String) -> DownloadedMedia {
        DownloadedMedia(
            id: id,
            videoID: "vid-\(id)",
            title: title,
            resolution: 720,
            fileURL: URL(fileURLWithPath: "/tmp/h3/\(id)/media.mp4"),
            sizeBytes: 1234,
            createdAt: Date()
        )
    }

    // MARK: - LibraryStore durability-critical rollback

    func testFailedSaveRollsBackDownloadIndexInsertAndFlagsDegraded() throws {
        let saver = SwitchableSaver()
        let store = LibraryStore(context: try makeContext(), saveHandler: { try saver.perform() })

        store.addDownloadedMedia(downloadedMedia(id: "a", title: "A"))

        XCTAssertTrue(store.downloaded.isEmpty, "failed insert must not leave a phantom offline entry")
        XCTAssertTrue(store.isPersistenceDegraded)
        XCTAssertFalse(store.isSaved(videoID: "vid-a"))
    }

    func testSuccessfulSaveClearsDegradedFlagAndCommits() throws {
        let saver = SwitchableSaver()
        let store = LibraryStore(context: try makeContext(), saveHandler: { try saver.perform() })
        store.addDownloadedMedia(downloadedMedia(id: "a", title: "A"))
        XCTAssertTrue(store.isPersistenceDegraded)

        saver.release()
        store.addDownloadedMedia(downloadedMedia(id: "b", title: "B"))

        XCTAssertFalse(store.isPersistenceDegraded, "next successful save clears the degraded signal")
        XCTAssertEqual(store.downloaded.map(\.id), ["b"], "rolled-back row stays absent; new row persists")
    }

    func testFailedSaveOnUpdatePathRestoresPriorFieldValues() throws {
        let saver = SwitchableSaver()
        let store = LibraryStore(context: try makeContext(), saveHandler: { try saver.perform() })

        // Seed durably.
        saver.release()
        store.addDownloadedMedia(downloadedMedia(id: "u", title: "Original"))
        XCTAssertEqual(store.downloaded.first?.title, "Original")

        // Re-arm failure and attempt an update of the same row.
        saver.rearm()
        var updated = downloadedMedia(id: "u", title: "Mutated")
        updated.sizeBytes = 999_999
        store.addDownloadedMedia(updated)

        XCTAssertTrue(store.isPersistenceDegraded)
        XCTAssertEqual(store.downloaded.first?.title, "Original",
                       "failed update must not leave mutated in-memory values behind")
        XCTAssertEqual(store.downloaded.first?.sizeBytes, 1234,
                       "prior durable field values are restored on rollback")
    }

    // MARK: - Session-tolerant optimistic state + degraded signal

    func testHistoryKeepsSessionUsabilityButSignalsDegradationOnFailedSave() throws {
        let store = LibraryStore(context: try makeContext(), saveHandler: {
            throw NSError(domain: "test", code: 4)
        })

        store.recordProgress(
            videoID: "v1",
            title: "V1",
            channelTitle: "C",
            position: 30,
            duration: 100,
            completed: false
        )

        // Session usability preserved (documented deliberate semantics).
        XCTAssertEqual(store.history.count, 1)
        XCTAssertEqual(store.history.first?.lastPositionSeconds, 30)
        // Truthfulness: the store explicitly says durability failed.
        XCTAssertTrue(store.isPersistenceDegraded)
    }

    // MARK: - RecentSearchStore write-through

    func testRecentsCommitOnlyAfterPersistenceSucceeds() throws {
        var shouldFail = false
        let store = RecentSearchStore(context: try {
            let schema = Schema([RecentSearchEntry.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return ModelContext(try ModelContainer(for: schema, configurations: [config]))
        }(), saveHandler: { if shouldFail { throw NSError(domain: "test", code: 5) } })

        store.record("swift")
        XCTAssertEqual(store.entries.map(\.query), ["swift"])
        XCTAssertFalse(store.isPersistenceDegraded)

        shouldFail = true
        store.record("failing-query")
        XCTAssertEqual(store.entries.map(\.query), ["swift"],
                       "failed persist must NOT advance the visible recents")
        XCTAssertTrue(store.isPersistenceDegraded)

        shouldFail = false
        store.record("concurrency")
        XCTAssertEqual(store.entries.map(\.query), ["concurrency", "swift"])
        XCTAssertFalse(store.isPersistenceDegraded)
    }

    func testRecentsClearIsGatedByPersistenceOutcome() throws {
        var shouldFail = true
        let store = RecentSearchStore(context: try {
            let schema = Schema([RecentSearchEntry.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return ModelContext(try ModelContainer(for: schema, configurations: [config]))
        }(), saveHandler: { if shouldFail { throw NSError(domain: "test", code: 6) } })

        shouldFail = false
        store.record("keep-me")

        shouldFail = true
        store.clear()
        XCTAssertEqual(store.entries.map(\.query), ["keep-me"],
                       "clear that cannot persist leaves durable truth visible")
        XCTAssertTrue(store.isPersistenceDegraded)
    }
}
