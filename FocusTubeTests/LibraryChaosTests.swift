import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// RELEASE_CONFIDENCE_V1 Wave 11 (persistence/filesystem chaos): the library
/// index must converge under repeated reconciliation, tolerate orphan/missing/
/// corrupted inputs, and never silently destroy recoverable user media.
@MainActor
final class LibraryChaosTests: XCTestCase {
    private func makeContainer(inMemory: Bool = true) throws -> ModelContainer {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTempFile(bytes: [UInt8]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-chaos-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }

    func testOrphanRowForMissingFileIsSweptRepeatedly() async throws {
        let store = LibraryStore(context: ModelContext(try makeContainer()))
        let missing = URL(fileURLWithPath: "/tmp/focustube-orphan-\(UUID().uuidString).mp4")
        await store.addDownloadedMedia(DownloadedMedia(
            id: "orphan", videoID: "v", title: "T", resolution: 480,
            fileURL: missing, sizeBytes: 0, createdAt: Date()
        ))

        for _ in 0..<3 {
            await store.reconcileDownloads()
        }
        let count = await store.downloaded.count
        XCTAssertEqual(count, 0, "repeated reconcile must converge on the swept state")
    }

    func testZeroByteExistingFileStaysListedUntilDeletedByUser() async throws {
        // A zero-byte file EXISTS; reconcile is a filesystem-existence sweep,
        // not a quality gate. Deletion of real files stays a user decision.
        let store = LibraryStore(context: ModelContext(try makeContainer()))
        let fileURL = try makeTempFile(bytes: [])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        await store.addDownloadedMedia(DownloadedMedia(
            id: "empty", videoID: "v", title: "T", resolution: 360,
            fileURL: fileURL, sizeBytes: 0, createdAt: Date()
        ))

        for _ in 0..<3 {
            await store.reconcileDownloads()
        }
        let count = await store.downloaded.count
        XCTAssertEqual(count, 1, "existing (even empty) user media must not be silently destroyed")
    }

    func testMixedIndexSurvivesTripleReconcileExactly() async throws {
        let store = LibraryStore(context: ModelContext(try makeContainer()))
        let liveA = try makeTempFile(bytes: [0x01])
        let liveB = try makeTempFile(bytes: [0x02, 0x03])
        defer {
            try? FileManager.default.removeItem(at: liveA)
            try? FileManager.default.removeItem(at: liveB)
        }
        let gone = URL(fileURLWithPath: "/tmp/focustube-gone-\(UUID().uuidString).mp4")

        await store.addDownloadedMedia(DownloadedMedia(id: "a", videoID: "va", title: "A", resolution: 720, fileURL: liveA, sizeBytes: 1, createdAt: Date()))
        await store.addDownloadedMedia(DownloadedMedia(id: "b", videoID: "vb", title: "B", resolution: 1080, fileURL: liveB, sizeBytes: 2, createdAt: Date(), channelTitle: "C"))
        await store.addDownloadedMedia(DownloadedMedia(id: "gone", videoID: "vg", title: "G", resolution: 360, fileURL: gone, sizeBytes: 0, createdAt: Date()))

        await store.reconcileDownloads()
        let afterFirst = await store.downloaded.map(\.id).sorted()
        XCTAssertEqual(afterFirst, ["a", "b"])

        for _ in 0..<2 {
            await store.reconcileDownloads()
        }
        let afterThird = await store.downloaded.map(\.id).sorted()
        XCTAssertEqual(afterThird, ["a", "b"], "idempotent convergence: no further mutation")
    }

    func testDeleteThenReconcileDoesNotResurrectRows() async throws {
        let store = LibraryStore(context: ModelContext(try makeContainer()))
        let fileURL = try makeTempFile(bytes: [0x09])
        defer { try? FileManager.default.removeItem(at: fileURL) }
        await store.addDownloadedMedia(DownloadedMedia(id: "d", videoID: "v", title: "T", resolution: 720, fileURL: fileURL, sizeBytes: 1, createdAt: Date()))

        await store.deleteDownloadedMedia(id: "d")
        for _ in 0..<3 {
            await store.reconcileDownloads()
        }
        let count = await store.downloaded.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "delete must remove the file, and no path may resurrect it")
    }

    func testProgressUpdateWithSameVideoIDNeverDuplicatesRows() async throws {
        let store = LibraryStore(context: ModelContext(try makeContainer()))
        for second in stride(from: 10.0, through: 90.0, by: 20.0) {
            await store.recordProgress(videoID: "same", title: "Same", channelTitle: "C", position: second, duration: 100, completed: false)
        }
        let count = await store.history.count
        XCTAssertEqual(count, 1, "progress ticks must upsert, never insert duplicates")
        let position = await store.resumePosition(for: "same")
        XCTAssertEqual(position, 90.0)
    }

    func testLegacyDownloadedRowWithoutChannelTitleStillDeletesCleanly() async throws {
        let container = try makeContainer()
        // Simulate a legacy row created before the additive optional existed.
        let context = ModelContext(container)
        context.insert(DownloadedMedia(
            id: "legacy", videoID: "vl", title: "Legacy",
            resolution: 480,
            fileURL: URL(fileURLWithPath: "/tmp/focustube-legacy-\(UUID().uuidString).mp4"),
            sizeBytes: 0,
            createdAt: Date(),
            channelTitle: nil
        ))
        try context.save()

        let store = LibraryStore(context: ModelContext(container))
        await store.reconcileDownloads()
        let count = await store.downloaded.count
        XCTAssertEqual(count, 0, "missing legacy file + nil channelTitle sweeps cleanly")
    }
}
