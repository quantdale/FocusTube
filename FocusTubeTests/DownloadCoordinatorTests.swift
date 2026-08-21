import XCTest
@testable import FocusTube
import FocusTubeCore

private struct NoopDownloadTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

private struct FakeFileManager: FileManaging {
    var exists = true
    var fileSize: Int64 = 1024
    var createDirThrows = false
    var replaceThrows = false

    func fileExists(at url: URL) -> Bool { exists }
    func size(of url: URL) -> Int64 { fileSize }
    func createDirectory(at url: URL) throws {
        if createDirThrows { throw NSError(domain: "fake", code: 1) }
    }
    func replaceItem(at destination: URL, withItemAt item: URL) throws {
        if replaceThrows { throw NSError(domain: "fake", code: 2) }
    }
    func moveItem(at item: URL, to destination: URL) throws {}
    func removeItem(at url: URL) throws {}
}

final class DownloadCoordinatorTests: XCTestCase {
    func makeRequest(id: String = "d1") -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "vid",
            streamID: "s1",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4")
        )
    }

    func testEnqueueIsQueued() async {
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: FakeFileManager())
        let task = await coordinator.enqueue(makeRequest())
        XCTAssertEqual(task.state.status, .queued)
    }

    func testProgressUpdatesBytes() async {
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: FakeFileManager())
        _ = await coordinator.enqueue(makeRequest())
        await coordinator.handle(.progress(component: 0, bytes: 50, total: 100), taskID: "d1")
        let task = await coordinator.task("d1")
        XCTAssertEqual(task?.state.bytesDownloaded, 50)
        XCTAssertEqual(task?.state.totalBytes, 100)
        XCTAssertEqual(task?.state.status, .queued)
    }

    func testCompletionFinalizesAndCompletes() async {
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: FakeFileManager())
        _ = await coordinator.enqueue(makeRequest())
        await coordinator.begin("d1")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/tmp-d1.mp4"), component: 0), taskID: "d1")
        let task = await coordinator.task("d1")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertNil(task?.state.error)
    }

    func testMissingTempFileFailsValidation() async {
        var fm = FakeFileManager()
        fm.exists = false
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: fm)
        _ = await coordinator.enqueue(makeRequest())
        await coordinator.begin("d1")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/missing.mp4"), component: 0), taskID: "d1")
        let task = await coordinator.task("d1")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .validationFailed)
    }

    func testReplaceFailureFailsFinalization() async {
        var fm = FakeFileManager()
        fm.replaceThrows = true
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: fm)
        _ = await coordinator.enqueue(makeRequest())
        await coordinator.begin("d1")
        await coordinator.handle(.completed(tempLocation: URL(fileURLWithPath: "/tmp/tmp-d1.mp4"), component: 0), taskID: "d1")
        let task = await coordinator.task("d1")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .finalizationFailed)
    }

    func testTransportFailureFails() async {
        let coordinator = DownloadCoordinator(transport: NoopDownloadTransport(), fileManager: FakeFileManager())
        _ = await coordinator.enqueue(makeRequest())
        await coordinator.handle(.failed(.transportFailed), taskID: "d1")
        let task = await coordinator.task("d1")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .transportFailed)
    }
}
