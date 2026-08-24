import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Fake transport whose background session "survived" a relaunch and still
/// holds live transfers for the given requests.
private actor RecoveringTransport: DownloadTransport {
    let recovered: [ReattachedDownload]
    private(set) var cancelledIDs: [String] = []

    /// Convenience for single-component requests: index 0 survived.
    init(recoveredIDs: [String]) {
        self.recovered = recoveredIDs.map { ReattachedDownload(requestID: $0, recoveredIndexes: [0]) }
    }

    init(recovered: [ReattachedDownload]) {
        self.recovered = recovered
    }

    func reattach(onEvent: @escaping @Sendable (String, DownloadEvent) -> Void) async -> [ReattachedDownload] {
        recovered
    }

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}

    func cancel(taskID: String) async {
        if !cancelledIDs.contains(taskID) {
            cancelledIDs.append(taskID)
        }
    }
}

private struct FakeStorage: StorageProviding {
    var capacity: Int64
    func availableCapacity(for url: URL) -> Int64 { capacity }
}

@MainActor
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

    func testEnqueuePersistsAdmittedRecordAsResolving() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        _ = await manager.enqueue(makeRequest(id: "a"))
        let records = await manager.records
        XCTAssertEqual(records.count, 1)
        // Admitted ⇒ slot-consuming: the record reads .resolving immediately
        // so capacity accounting is truthful during the transfer window.
        XCTAssertEqual(records.first?.state.status, .resolving)
    }

    func testReEnqueueSameIDUpsertsInsteadOfDuplicating() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        _ = await manager.enqueue(makeRequest(id: "dup"))
        _ = await manager.enqueue(makeRequest(id: "dup"))
        let records = await manager.records
        XCTAssertEqual(records.count, 1)
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

    func testFullyRecoveredAdaptiveTaskAttachesWithExplicitIndexes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var task = DownloadTask(
            id: "pair",
            videoID: "v",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/pair.mp4"),
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        task.apply(DownloadState(status: .downloading))
        context.insert(DownloadRecord(task: task))
        try context.save()

        // Both components survived; report them out of order to prove
        // reattachment keys on explicit indexes, not enumeration position.
        let transport = RecoveringTransport(recovered: [
            ReattachedDownload(requestID: "pair", recoveredIndexes: [1, 0])
        ])
        let manager = await DownloadManager(transport: transport, context: ModelContext(container))
        await manager.reconcileOnLaunch()

        let records = await manager.records
        XCTAssertEqual(records.first(where: { $0.id == "pair" })?.state.status, .downloading)
        let coordinatorTask = await manager.coordinatorTask("pair")
        XCTAssertEqual(coordinatorTask?.id, "pair")
        XCTAssertEqual(coordinatorTask?.state.status, .downloading)
    }

    func testPartiallyRecoveredAdaptiveTaskFailsInterrupted() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var task = DownloadTask(
            id: "pair",
            videoID: "v",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/pair.mp4"),
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        task.apply(DownloadState(status: .downloading))
        context.insert(DownloadRecord(task: task))
        try context.save()

        // Only the audio component survived the relaunch; the pair can never
        // finalize, so it must fail as interrupted instead of hanging.
        let transport = RecoveringTransport(recovered: [
            ReattachedDownload(requestID: "pair", recoveredIndexes: [1])
        ])
        let manager = await DownloadManager(transport: transport, context: ModelContext(container))
        await manager.reconcileOnLaunch()

        let records = await manager.records
        XCTAssertEqual(records.first(where: { $0.id == "pair" })?.state.status, .failed)
        XCTAssertEqual(records.first(where: { $0.id == "pair" })?.state.error, .interrupted)
        // The doomed job is never attached to the coordinator.
        let coordinatorTask = await manager.coordinatorTask("pair")
        XCTAssertNil(coordinatorTask)
        // Surviving transfers are cancelled so the background session drains.
        let cancelled = await transport.cancelledIDs
        XCTAssertEqual(cancelled, ["pair"])
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

    func testThirdRequestAtCapacityLimitPersistsQueuedWithoutCoordinatorTask() async throws {
        // docs/03: at most two concurrent logical downloads. The first two
        // occupy the slots (queued records count as active); the third must
        // persist as .queued without a coordinator transfer to promote later.
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        _ = await manager.enqueue(makeRequest(id: "s1"))
        _ = await manager.enqueue(makeRequest(id: "s2"))
        let third = await manager.enqueue(makeRequest(id: "s3"))

        XCTAssertEqual(third.state.status, .queued)
        let records = await manager.records
        XCTAssertEqual(records.count, 3)
        let thirdCoordinatorTask = await manager.coordinatorTask("s3")
        XCTAssertNil(thirdCoordinatorTask)
        // Occupying requests are tracked by the coordinator as usual.
        let firstCoordinatorTask = await manager.coordinatorTask("s1")
        XCTAssertNotNil(firstCoordinatorTask)
    }

    func testPresentationMetadataRoundTripsAndLegacyRowsFallBackToNil() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        // Legacy row created before the additive metadata fields existed.
        _ = await manager.enqueue(makeRequest(id: "legacy"))
        let legacyMetadata = await manager.presentationMetadata(taskID: "legacy")
        XCTAssertNil(legacyMetadata?.title)
        XCTAssertNil(legacyMetadata?.channelTitle)

        await manager.setPresentationMetadata(taskID: "legacy", title: "Real", channelTitle: "Channel")
        let stored = await manager.presentationMetadata(taskID: "legacy")
        XCTAssertEqual(stored?.title, "Real")
        XCTAssertEqual(stored?.channelTitle, "Channel")
    }

    func testCancelReleasesAdmissionReservation() async throws {
        let manager = await DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(try makeContainer())
        )
        let reserved = await manager.reserveAdmission("r1")
        XCTAssertTrue(reserved)
        let reReserve = await manager.reserveAdmission("r1")
        XCTAssertFalse(reReserve)
        await manager.cancel("r1")
        let afterCancel = await manager.reserveAdmission("r1")
        XCTAssertTrue(afterCancel)
    }

    // MARK: - H2-005 reattached-event ordering

    /// Emits a scripted burst of reattached events back-to-back synchronously
    /// inside `reattach`, mimicking URLSession delegate delivery order.
    private actor BurstTransport: DownloadTransport {
        let requestID: String
        let events: [DownloadEvent]

        init(requestID: String, events: [DownloadEvent]) {
            self.requestID = requestID
            self.events = events
        }

        func reattach(onEvent: @escaping @Sendable (String, DownloadEvent) -> Void) async -> [ReattachedDownload] {
            for event in events {
                onEvent(requestID, event)
            }
            return [ReattachedDownload(requestID: requestID, recoveredIndexes: [0])]
        }

        func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}

        func cancel(taskID: String) async {}
    }

    /// Reattached progress/terminal events must apply in delivery order: the
    /// last persisted byte count must be the newest progress (100), and the
    /// terminal event must settle after it — never be overtaken by an older
    /// progress hopping through its own unstructured task.
    func testReattachedEventsApplyInDeliveryOrder() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertRecord("burst", into: context, status: .downloading)

        let transport = BurstTransport(requestID: "burst", events: [
            .progress(component: 0, bytes: 50, total: 100),
            .progress(component: 0, bytes: 100, total: 100),
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/staged-burst"), component: 0)
        ])
        let manager = await DownloadManager(
            transport: transport,
            context: ModelContext(container)
        )
        await manager.reconcileOnLaunch()

        // The completed event finalizes against a nonexistent staged temp and
        // settles validationFailed; both progress events must already have
        // applied in order before that settle.
        var settledTask: DownloadTask?
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            settledTask = await manager.coordinatorTask("burst")
            if let status = settledTask?.state.status, status == .failed || status == .completed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let task = try XCTUnwrap(settledTask)
        XCTAssertEqual(task.state.bytesDownloaded, 100, "newest progress must win; stale 50 must not persist after settle")
        XCTAssertEqual(task.state.totalBytes, 100)
        XCTAssertEqual(task.state.status, .failed)
        XCTAssertEqual(task.state.error, .validationFailed)
    }

    /// Recovery transport that counts every reattach invocation and fires the
    /// scripted burst synchronously per call — proving that overlapping
    /// reconciliation callers coalesce into a single pass instead of
    /// duplicating delivery.
    private actor CountingBurstTransport: DownloadTransport {
        let requestID: String
        let events: [DownloadEvent]
        private(set) var reattachCount = 0

        init(requestID: String, events: [DownloadEvent]) {
            self.requestID = requestID
            self.events = events
        }

        func reattach(onEvent: @escaping @Sendable (String, DownloadEvent) -> Void) async -> [ReattachedDownload] {
            reattachCount += 1
            for event in events {
                onEvent(requestID, event)
            }
            return [ReattachedDownload(requestID: requestID, recoveredIndexes: [0])]
        }

        func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}

        func cancel(taskID: String) async {}
    }

    /// Overlapping/reentrant reconcile requests (the init-spawned launch task
    /// plus explicit concurrent calls) must coalesce into exactly one pass:
    /// one underlying transport reattachment, no duplicate event delivery,
    /// burst applied 50 → 100 → terminal in order, and newest cumulative
    /// progress surviving settlement.
    func testOverlappingReconcileRequestsCoalesceIntoSinglePass() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try insertRecord("burst", into: context, status: .downloading)

        let transport = CountingBurstTransport(requestID: "burst", events: [
            .progress(component: 0, bytes: 50, total: 100),
            .progress(component: 0, bytes: 100, total: 100),
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/staged-burst"), component: 0)
        ])
        let manager = await DownloadManager(
            transport: transport,
            context: ModelContext(container)
        )
        // Race explicit calls against each other and against whatever the
        // init-spawned reconcile is doing; every caller must join or observe
        // the single completed pass.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await manager.reconcileOnLaunch()
                }
            }
        }

        let reattachCalls = await transport.reattachCount
        XCTAssertEqual(reattachCalls, 1, "overlapping reconcile callers must not double-fire reattachment")

        var settledTask: DownloadTask?
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            settledTask = await manager.coordinatorTask("burst")
            if let status = settledTask?.state.status, status == .failed || status == .completed {
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let task = try XCTUnwrap(settledTask)
        XCTAssertEqual(task.state.bytesDownloaded, 100)
        XCTAssertEqual(task.state.totalBytes, 100)
        XCTAssertEqual(task.state.status, .failed)
        XCTAssertEqual(task.state.error, .validationFailed)
    }
}
