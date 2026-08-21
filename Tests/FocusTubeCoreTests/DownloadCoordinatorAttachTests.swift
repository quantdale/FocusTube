import XCTest
@testable import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Ordered journal entry for filesystem mutations, so tests can assert
/// relative ordering (e.g. a stale destination removed before the validated
/// mux product moves into place).
private enum FileOp: Equatable {
    case removed(URL)
    case replaced(URL)
    case moved(item: URL, destination: URL)
}

/// Records filesystem mutations so tests can assert which transient files the
/// coordinator removes or moves during finalization.
private final class TempFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [URL] = []
    private var replaced: [URL] = []
    private var moved: [(item: URL, destination: URL)] = []
    private var ops: [FileOp] = []
    /// Last known existence per URL; removals and moves mutate it.
    private var existence: [URL: Bool] = [:]
    private var muxCalls: [(components: [URL], output: URL)] = []

    func recordRemoval(_ url: URL) {
        lock.lock()
        removed.append(url)
        ops.append(.removed(url))
        existence[url] = false
        lock.unlock()
    }

    func recordReplacement(_ url: URL) {
        lock.lock()
        replaced.append(url)
        ops.append(.replaced(url))
        lock.unlock()
    }

    func recordMove(item: URL, destination: URL) {
        lock.lock()
        moved.append((item, destination))
        ops.append(.moved(item: item, destination: destination))
        existence[destination] = true
        lock.unlock()
    }

    func recordMux(components: [URL], output: URL) {
        lock.lock()
        muxCalls.append((components, output))
        lock.unlock()
    }

    /// Overlay-aware existence lookup; falls back when the URL was never
    /// removed or written through the recorder.
    func existence(of url: URL, fallback: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return existence[url] ?? fallback
    }

    var removedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return removed
    }

    var replacedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return replaced
    }

    var movedItems: [(item: URL, destination: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return moved
    }

    var recordedOps: [FileOp] {
        lock.lock()
        defer { lock.unlock() }
        return ops
    }

    var recordedMuxCalls: [(components: [URL], output: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return muxCalls
    }
}

private struct RecordingFileManager: FileManaging {
    var exists = true
    var fileSize: Int64 = 1024
    let recorder: TempFileRecorder
    /// URLs reported as non-existent regardless of `exists` (e.g. a first-time
    /// destination slot that has no file yet).
    var hiddenURLs: Set<URL> = []

    func fileExists(at url: URL) -> Bool {
        let base = hiddenURLs.contains(url)
            ? recorder.movedItems.contains { $0.destination == url }
            : exists
        return recorder.existence(of: url, fallback: base)
    }
    func size(of url: URL) -> Int64 { fileSize }
    func createDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt item: URL) throws {
        recorder.recordReplacement(item)
    }
    func moveItem(at item: URL, to destination: URL) throws {
        recorder.recordMove(item: item, destination: destination)
    }
    func removeItem(at url: URL) throws {
        recorder.recordRemoval(url)
    }
}

final class DownloadCoordinatorAttachTests: XCTestCase {
    func makeRequest(id: String) -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "vid",
            streamID: "s1",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4")
        )
    }

    // MARK: - attach keying

    func testAttachRegistersUnderTaskIDNotRequestID() async {
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: TempFileRecorder())
        )
        await coordinator.attach(taskID: "task-1", request: makeRequest(id: "request-1"))
        let attached = await coordinator.task("task-1")
        XCTAssertEqual(attached?.id, "task-1")
        XCTAssertEqual(attached?.state.status, .downloading)
        let unattached = await coordinator.task("request-1")
        XCTAssertNil(unattached)
    }

    func testEventsDriveAttachedTaskByTaskID() async {
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: TempFileRecorder())
        )
        await coordinator.attach(taskID: "task-1", request: makeRequest(id: "request-1"))
        await coordinator.handle(.progress(component: 0, bytes: 40, total: 80), taskID: "task-1")
        let task = await coordinator.task("task-1")
        XCTAssertEqual(task?.state.bytesDownloaded, 40)
        XCTAssertEqual(task?.state.totalBytes, 80)
    }

    func testAttachedSingleComponentTaskFinalizes() async {
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: TempFileRecorder())
        )
        await coordinator.attach(taskID: "task-1", request: makeRequest(id: "task-1"))
        await coordinator.handle(
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/tmp-task-1.mp4"), component: 0),
            taskID: "task-1"
        )
        let task = await coordinator.task("task-1")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertNil(task?.state.error)
    }

    // MARK: - post-finalize temp cleanup

    func testAdaptiveCompletionRemovesComponentTempFiles() async {
        let recorder = TempFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { components, output in
            recorder.recordMux(components: components, output: output)
            return output
        }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
            directory: URL(fileURLWithPath: "/tmp/work"),
            mux: mux
        )
        let videoTemp = URL(fileURLWithPath: "/tmp/ad-video.m4s")
        let audioTemp = URL(fileURLWithPath: "/tmp/ad-audio.m4s")
        let destination = URL(fileURLWithPath: "/tmp/ad.mp4")
        let request = DownloadRequest(
            id: "ad",
            videoID: "vid",
            resolution: 1080,
            destinationURL: destination,
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("ad")
        await coordinator.handle(.completed(tempLocation: videoTemp, component: 0), taskID: "ad")
        await coordinator.handle(.completed(tempLocation: audioTemp, component: 1), taskID: "ad")

        let task = await coordinator.task("ad")
        XCTAssertEqual(task?.state.status, .completed)

        // Mux ran exactly once, into a transient work-directory file that is
        // not the destination.
        XCTAssertEqual(recorder.recordedMuxCalls.count, 1)
        let muxCall = recorder.recordedMuxCalls[0]
        XCTAssertEqual(muxCall.components, [videoTemp, audioTemp])
        XCTAssertNotEqual(muxCall.output, destination)
        XCTAssertEqual(muxCall.output.deletingLastPathComponent().path, "/tmp/work")
        XCTAssertTrue(muxCall.output.lastPathComponent.hasPrefix(destination.lastPathComponent + ".muxing-"))

        // Publish path: stale destination deleted, validated output moved in,
        // component temps cleaned up — never a direct write to the destination.
        XCTAssertEqual(Set(recorder.removedURLs), Set([videoTemp, audioTemp, destination]))
        XCTAssertEqual(recorder.movedItems.count, 1)
        XCTAssertEqual(recorder.movedItems.first?.item, muxCall.output)
        XCTAssertEqual(recorder.movedItems.first?.destination, destination)
        guard let removeOp = recorder.recordedOps.firstIndex(where: { $0 == .removed(destination) }),
              let moveOp = recorder.recordedOps.firstIndex(where: {
                  $0 == .moved(item: muxCall.output, destination: destination)
              }) else {
            return XCTFail("expected destination removal and final move to be recorded")
        }
        XCTAssertLessThan(removeOp, moveOp)
    }

    func testAdaptiveMuxThrowingLeavesDestinationIntact() async {
        let recorder = TempFileRecorder()
        struct Boom: Error {}
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, _ in throw Boom() }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
            directory: URL(fileURLWithPath: "/tmp/work"),
            mux: mux
        )
        let request = DownloadRequest(
            id: "boom",
            videoID: "vid",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/boom.mp4"),
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("boom")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/b-v.m4s"), component: 0), taskID: "boom")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/b-a.m4s"), component: 1), taskID: "boom")

        let task = await coordinator.task("boom")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .muxFailed)
        // An interrupted export must not damage an existing final file.
        XCTAssertFalse(recorder.removedURLs.contains(URL(fileURLWithPath: "/tmp/boom.mp4")))
        XCTAssertTrue(recorder.movedItems.isEmpty)
    }

    func testCompletedEventsMapToExactComponentSlotsRegardlessOfArrivalOrder() async {
        let recorder = TempFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { components, output in
            recorder.recordMux(components: components, output: output)
            return output
        }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
            directory: URL(fileURLWithPath: "/tmp/work"),
            mux: mux
        )
        let request = DownloadRequest(
            id: "pair",
            videoID: "vid",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/pair.mp4"),
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("pair")
        // Audio (component 1) finishes first, as happens on real networks;
        // slots must follow the event's component index, not arrival order.
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/p-audio.m4s"), component: 1), taskID: "pair")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/p-video.m4s"), component: 0), taskID: "pair")

        let task = await coordinator.task("pair")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertEqual(
            recorder.recordedMuxCalls.first?.components,
            [
                URL(fileURLWithPath: "/tmp/p-video.m4s"),
                URL(fileURLWithPath: "/tmp/p-audio.m4s")
            ]
        )
    }

    func testSingleComponentCompletionMovesTempViaReplaceWithoutRemoval() async {
        let recorder = TempFileRecorder()
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder)
        )
        _ = await coordinator.enqueue(makeRequest(id: "single"))
        await coordinator.begin("single")
        let temp = URL(fileURLWithPath: "/tmp/tmp-single.mp4")
        await coordinator.handle(.completed(tempLocation: temp, component: 0), taskID: "single")

        let task = await coordinator.task("single")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertEqual(recorder.replacedURLs, [temp])
        XCTAssertTrue(recorder.removedURLs.isEmpty)
    }

    // MARK: - first-time finalization

    func testFirstDownloadMovesTempWhenDestinationDoesNotExist() async {
        let recorder = TempFileRecorder()
        let destination = URL(fileURLWithPath: "/tmp/fresh-single.mp4")
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder, hiddenURLs: [destination])
        )
        var request = makeRequest(id: "fresh")
        request = DownloadRequest(
            id: request.id,
            videoID: request.videoID,
            streamID: "s1",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/fresh")!,
            destinationURL: destination
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("fresh")
        let temp = URL(fileURLWithPath: "/tmp/tmp-fresh.mp4")
        await coordinator.handle(.completed(tempLocation: temp, component: 0), taskID: "fresh")

        let task = await coordinator.task("fresh")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertNil(task?.state.error)
        XCTAssertEqual(recorder.movedItems.count, 1)
        XCTAssertEqual(recorder.movedItems.first?.item, temp)
        XCTAssertEqual(recorder.movedItems.first?.destination, destination)
        XCTAssertTrue(recorder.replacedURLs.isEmpty)
    }

    // MARK: - transfer identity codec

    func testDownloadTransferIdentityRoundTripsThroughDescription() {
        let encoded = DownloadTransferIdentity.encode(requestID: "req-1", componentIndex: 1)
        XCTAssertEqual(encoded, "req-1#1")
        let decoded = DownloadTransferIdentity.decode(encoded)
        XCTAssertEqual(decoded?.requestID, "req-1")
        XCTAssertEqual(decoded?.componentIndex, 1)

        // UUID-shaped request ids (the production shape) round-trip exactly
        // for every adaptive slot.
        for index in 0..<2 {
            let id = UUID().uuidString
            let roundTripped = DownloadTransferIdentity.decode(
                DownloadTransferIdentity.encode(requestID: id, componentIndex: index)
            )
            XCTAssertEqual(roundTripped?.requestID, id)
            XCTAssertEqual(roundTripped?.componentIndex, index)
        }
    }

    func testDownloadTransferIdentityRejectsMalformedDescriptions() {
        XCTAssertNil(DownloadTransferIdentity.decode(nil))
        XCTAssertNil(DownloadTransferIdentity.decode(""))
        XCTAssertNil(DownloadTransferIdentity.decode("req-without-index"))
        XCTAssertNil(DownloadTransferIdentity.decode("#0")) // empty request id
        XCTAssertNil(DownloadTransferIdentity.decode("req#x")) // non-numeric index
        XCTAssertNil(DownloadTransferIdentity.decode("req#-1")) // negative index
    }
}
