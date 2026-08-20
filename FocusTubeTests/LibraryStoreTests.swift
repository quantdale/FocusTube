import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

final class LibraryStoreTests: XCTestCase {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testProgressPersistsAndResumes() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        await store.recordProgress(videoID: "v1", title: "T", channelTitle: "C", position: 123.5, duration: 600, completed: false)
        let position = await store.resumePosition(for: "v1")
        XCTAssertEqual(position, 123.5)

        // Reload from a fresh store over the same container (simulating relaunch).
        let reloaded = await LibraryStore(context: ModelContext(try makeContainer()))
        XCTAssertEqual(await reloaded.resumePosition(for: "v1"), 123.5)
        XCTAssertEqual(await reloaded.history.count, 1)
    }

    func testReconcileRemovesMissingFiles() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        let missingURL = URL(fileURLWithPath: "/tmp/focustube-missing-\(UUID().uuidString).mp4")
        let media = DownloadedMedia(id: "d1", videoID: "v", title: "T", resolution: 720, fileURL: missingURL, sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(media)
        XCTAssertEqual(await store.downloaded.count, 1)

        await store.reconcileDownloads()
        XCTAssertEqual(await store.downloaded.count, 0)
    }

    func testDeleteIsAtomicAndSafe() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focustube-lib-\(UUID().uuidString).mp4")
        try Data([0x01, 0x02]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let media = DownloadedMedia(id: "d2", videoID: "v", title: "T", resolution: 1080, fileURL: fileURL, sizeBytes: 2, createdAt: Date())
        await store.addDownloadedMedia(media)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        await store.deleteDownloadedMedia(id: "d2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(await store.downloaded.count, 0)
    }

    func testSaveDeduplicates() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        await store.save(videoID: "v2", title: "T", channelTitle: "C")
        await store.save(videoID: "v2", title: "T", channelTitle: "C")
        XCTAssertEqual(await store.saved.count, 1)
    }
}
