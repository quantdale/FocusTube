import XCTest
@testable import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Records filesystem mutations so tests can assert which transient files the
/// coordinator removes or moves during finalization.
private final class TempFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [URL] = []
    private var replaced: [URL] = []
    private var moved: [(item: URL, destination: URL)] = []

    func recordRemoval(_ url: URL) {
        lock.lock()
        removed.append(url)
        lock.unlock()
    }

    func recordReplacement(_ url: URL) {
        lock.lock()
        replaced.append(url)
        lock.unlock()
    }

    func recordMove(item: URL, destination: URL) {
        lock.lock()
        moved.append((item, destination))
        lock.unlock()
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
}

private struct RecordingFileManager: FileManaging {
    var exists = true
    var fileSize: Int64 = 1024
    let recorder: TempFileRecorder
    /// URLs reported as non-existent regardless of `exists` (e.g. a first-time
    /// destination slot that has no file yet).
    var hiddenURLs: Set<URL> = []

    func fileExists(at url: URL) -> Bool {
        if hiddenURLs.contains(url) {
            // A hidden slot starts empty but comes into existence once a
            // recorded move placed an item there.
            return recorder.movedItems.contains { $0.destination == url }
        }
        return exists
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
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, destination in destination }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
            mux: mux
        )
        let videoTemp = URL(fileURLWithPath: "/tmp/ad-video.m4s")
        let audioTemp = URL(fileURLWithPath: "/tmp/ad-audio.m4s")
        let request = DownloadRequest(
            id: "ad",
            videoID: "vid",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/ad.mp4"),
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
        XCTAssertEqual(Set(recorder.removedURLs), Set([videoTemp, audioTemp]))
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
}
