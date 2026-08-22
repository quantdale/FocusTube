import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// Fake file manager whose removal can be made to fail with a chosen error,
/// so delete-ordering behavior is observable without real filesystem faults.
private final class FaultingFileManager: FileManaging, @unchecked Sendable {
    var removeError: NSError?

    func fileExists(at url: URL) -> Bool { false }
    func size(of url: URL) -> Int64 { 0 }
    func createDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt item: URL) throws {}
    func moveItem(at item: URL, to destination: URL) throws {}
    func removeItem(at url: URL) throws {
        if let removeError { throw removeError }
    }
}

@MainActor
final class LibraryStoreTests: XCTestCase {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testProgressPersistsAndResumes() async throws {
        let container = try makeContainer()
        let store = await LibraryStore(context: ModelContext(container))
        await store.recordProgress(videoID: "v1", title: "T", channelTitle: "C", position: 123.5, duration: 600, completed: false)
        let position = await store.resumePosition(for: "v1")
        XCTAssertEqual(position, 123.5)

        // Reload from a fresh store over the same container (simulating relaunch).
        let reloaded = await LibraryStore(context: ModelContext(container))
        let reloadedPosition = await reloaded.resumePosition(for: "v1")
        XCTAssertEqual(reloadedPosition, 123.5)
        let reloadedHistoryCount = await reloaded.history.count
        XCTAssertEqual(reloadedHistoryCount, 1)
    }

    func testReconcileRemovesMissingFiles() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        let missingURL = URL(fileURLWithPath: "/tmp/focustube-missing-\(UUID().uuidString).mp4")
        let media = DownloadedMedia(id: "d1", videoID: "v", title: "T", resolution: 720, fileURL: missingURL, sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(media)
        let countAfterAdd = await store.downloaded.count
        XCTAssertEqual(countAfterAdd, 1)

        await store.reconcileDownloads()
        let countAfterReconcile = await store.downloaded.count
        XCTAssertEqual(countAfterReconcile, 0)
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
        let countAfterDelete = await store.downloaded.count
        XCTAssertEqual(countAfterDelete, 0)
    }

    func testSaveDeduplicates() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        await store.save(videoID: "v2", title: "T", channelTitle: "C")
        await store.save(videoID: "v2", title: "T", channelTitle: "C")
        let savedCount = await store.saved.count
        XCTAssertEqual(savedCount, 1)
    }

    func testUpsertNeverDowngradesRealTitleToVideoIDPlaceholder() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        let media = DownloadedMedia(id: "d3", videoID: "v3", title: "Real Title", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/x.mp4"), sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(media)

        // Background completion registering later only knows the videoID.
        let placeholder = DownloadedMedia(id: "d3", videoID: "v3", title: "v3", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/x.mp4"), sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(placeholder)

        let downloaded = await store.downloaded
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.title, "Real Title")
    }

    func testUpsertUpgradesPlaceholderToRealTitle() async throws {
        let store = await LibraryStore(context: ModelContext(try makeContainer()))
        let placeholder = DownloadedMedia(id: "d4", videoID: "v4", title: "v4", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/y.mp4"), sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(placeholder)

        let real = DownloadedMedia(id: "d4", videoID: "v4", title: "Better Title", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/y.mp4"), sizeBytes: 5, createdAt: Date(), channelTitle: "Chan")
        await store.addDownloadedMedia(real)

        let downloaded = await store.downloaded
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.title, "Better Title")
        XCTAssertEqual(downloaded.first?.channelTitle, "Chan")
        XCTAssertEqual(downloaded.first?.sizeBytes, 5)
    }

    func testDeleteKeepsRowWhenRemovalFailsWithRealError() async throws {
        let files = FaultingFileManager()
        files.removeError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: nil)
        let store = await LibraryStore(context: ModelContext(try makeContainer()), fileManager: files)
        let media = DownloadedMedia(id: "d5", videoID: "v", title: "T", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/stuck.mp4"), sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(media)

        await store.deleteDownloadedMedia(id: "d5")
        let count = await store.downloaded.count
        XCTAssertEqual(count, 1, "metadata must survive a failed file removal so the entry stays diagnosable/deletable")
    }

    func testDeleteRemovesRowWhenFileAlreadyMissing() async throws {
        let files = FaultingFileManager()
        files.removeError = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        let store = await LibraryStore(context: ModelContext(try makeContainer()), fileManager: files)
        let media = DownloadedMedia(id: "d6", videoID: "v", title: "T", resolution: 720, fileURL: URL(fileURLWithPath: "/tmp/gone.mp4"), sizeBytes: 0, createdAt: Date())
        await store.addDownloadedMedia(media)

        await store.deleteDownloadedMedia(id: "d6")
        let count = await store.downloaded.count
        XCTAssertEqual(count, 0, "a missing file must not block metadata cleanup (no orphan row)")
    }
}
