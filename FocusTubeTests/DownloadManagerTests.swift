import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Fake transport whose background session "survived" a relaunch and still
/// holds live transfers for the given request ids.
private struct RecoveringTransport: DownloadTransport {
    let recoveredIDs: [String]

    func reattach(onEvent: @escaping @Sendable (String, DownloadEvent) -> Void) async -> [ReattachedDownload] {
        recoveredIDs.map { ReattachedDownload(requestID: $0, componentCount: 1) }
    }
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

    func insertRecord(_ id: String, into context: ModelContext, status: DownloadStatus) throws {
        var task = DownloadTask(
            id: id,
            videoID: "v",
            resolution: 720,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4"),
            components: [DownloadComponent(streamID: "s\(id)", sourceURL: URL(string: "https://example.com/\(id)")!)]
        )
        task.apply(DownloadState(status: status))
        context.insert(DownloadRecord(task: task))
        try context.save()
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
        await reloaded.reconcileOnLaunch()
        let records = await reloaded.records
        XCTAssertEqual(records.first?.state.status, .failed)
        XCTAssertEqual(records.first?.state.error, .interrupted)
    }

    func testReconcileReattachesRecoveredTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertRecord("keep", into: context, status: .downloading)

        // The background session survived the relaunch and still holds "keep".
        let manager = await DownloadManager(
            transport: RecoveringTransport(recoveredIDs: ["keep"]),
            context: ModelContext(container)
        )
        await manager.reconcileOnLaunch()

        let records = await manager.records
        XCTAssertEqual(records.first(where: { $0.id == "keep" })?.state.status, .downloading)
        let coordinatorTask = await manager.coordinatorTask("keep")
        XCTAssertEqual(coordinatorTask?.id, "keep")
        XCTAssertEqual(coordinatorTask?.state.status, .downloading)
    }

    func testReconcileInterruptsUnrecoveredTask() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertRecord("kept", into: context, status: .downloading)
        try insertRecord("dropped", into: context, status: .downloading)

        // Only "kept" comes back from the background session.
        let manager = await DownloadManager(
            transport: RecoveringTransport(recoveredIDs: ["kept"]),
            context: ModelContext(container)
        )
        await manager.reconcileOnLaunch()

        let records = await manager.records
        XCTAssertEqual(records.first(where: { $0.id == "kept" })?.state.status, .downloading)
        XCTAssertEqual(records.first(where: { $0.id == "dropped" })?.state.status, .failed)
        XCTAssertEqual(records.first(where: { $0.id == "dropped" })?.state.error, .interrupted)
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
