import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

private struct FakeStorage: StorageProviding {
    var capacity: Int64
    func availableCapacity(for url: URL) -> Int64 { capacity }
}

final class DownloadManagerTests: XCTestCase {
    func makeContainer() throws -> ModelContainer {
        let schema = Schema([DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func makeRequest(id: String) -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "v",
            streamID: "s\(id)",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4")
        )
    }

    func testEnqueuePersistsQueuedRecord() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        _ = await manager.enqueue(makeRequest(id: "a"))
        let records = await manager.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.state.status, .queued)
    }

    func testStorageRefusalPersistsFailedRecord() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer()),
            storage: FakeStorage(capacity: 100)
        )
        _ = await manager.enqueue(makeRequest(id: "b"), requiredBytes: 10_000)
        let records = await manager.records
        XCTAssertEqual(records.first?.state.status, .failed)
        XCTAssertEqual(records.first?.state.error, .storageRefused)
    }

    func testReconcileMarksInterruptedDownload() async throws {
        let container = try makeContainer()
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(container)
        )
        _ = await manager.enqueue(makeRequest(id: "c"))
        // Simulate a download that was mid-flight at relaunch.
        let context = ModelContext(container)
        let record = try context.fetch(FetchDescriptor<DownloadRecord>()).first!
        record.statusRaw = DownloadStatus.downloading.rawValue
        try context.save()

        // New manager reconciles the persisted record on launch (same container).
        let reloaded = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(container)
        )
        let records = await reloaded.records
        XCTAssertEqual(records.first?.state.status, .failed)
        XCTAssertEqual(records.first?.state.error, .interrupted)
    }

    func testCancelCleansUpRecord() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        _ = await manager.enqueue(makeRequest(id: "d"))
        await manager.cancel("d")
        let records = await manager.records
        XCTAssertEqual(records.first?.state.status, .failed)
        XCTAssertEqual(records.first?.state.error, .cancelled)
    }
}
