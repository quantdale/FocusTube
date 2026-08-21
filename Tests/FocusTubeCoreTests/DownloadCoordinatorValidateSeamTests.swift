import XCTest
@testable import FocusTubeCore

private struct SeamNoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Existence/mutation recorder mirroring the attach-tests pattern, scoped to
/// this file so finalization assertions stay deterministic without real I/O.
private final class SeamFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [URL] = []
    private var moved: [(item: URL, destination: URL)] = []
    private var existence: [URL: Bool] = [:]

    func recordRemoval(_ url: URL) {
        lock.lock()
        removed.append(url)
        existence[url] = false
        lock.unlock()
    }

    func recordMove(item: URL, destination: URL) {
        lock.lock()
        moved.append((item, destination))
        existence[destination] = true
        lock.unlock()
    }

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

    var movedItems: [(item: URL, destination: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return moved
    }
}

private struct SeamRecordingFileManager: FileManaging {
    var exists = true
    var fileSize: Int64 = 1024
    let recorder: SeamFileRecorder

    func fileExists(at url: URL) -> Bool {
        recorder.existence(of: url, fallback: exists)
    }
    func size(of url: URL) -> Int64 { fileSize }
    func createDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt item: URL) throws {}
    func moveItem(at item: URL, to destination: URL) throws {
        recorder.recordMove(item: item, destination: destination)
    }
    func removeItem(at url: URL) throws {
        recorder.recordRemoval(url)
    }
}

/// Coverage for the injected deep-validation seam (HB-010): a finalized file
/// that fails validation must settle as `.failed`/`.validationFailed` and be
/// discarded, never registered as a playable download; a passing validator
/// leaves the normal completion path untouched.
final class DownloadCoordinatorValidateSeamTests: XCTestCase {
    private struct ValidatorBoom: Error {}

    private func makeRequest(id: String) -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "vid",
            streamID: "s1",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4")
        )
    }

    // MARK: - combined path

    func testFailingValidatorDiscardsCombinedFinal() async {
        let recorder = SeamFileRecorder()
        let coordinator = DownloadCoordinator(
            transport: SeamNoopTransport(),
            fileManager: SeamRecordingFileManager(recorder: recorder),
            validate: { _ in throw ValidatorBoom() }
        )
        await coordinator.attach(taskID: "task-1", request: makeRequest(id: "task-1"))
        await coordinator.handle(
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/tmp-task-1.mp4"), component: 0),
            taskID: "task-1"
        )

        let task = await coordinator.task("task-1")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .validationFailed)
        XCTAssertTrue(recorder.removedURLs.contains(URL(fileURLWithPath: "/tmp/task-1.mp4")))
    }

    func testPassingValidatorCompletesCombinedFinal() async {
        let recorder = SeamFileRecorder()
        let coordinator = DownloadCoordinator(
            transport: SeamNoopTransport(),
            fileManager: SeamRecordingFileManager(recorder: recorder),
            validate: { _ in }
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

    // MARK: - adaptive path

    func testFailingValidatorDiscardsAdaptiveMuxProductAndTemps() async {
        let recorder = SeamFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, output in output }
        let coordinator = DownloadCoordinator(
            transport: SeamNoopTransport(),
            fileManager: SeamRecordingFileManager(recorder: recorder),
            directory: URL(fileURLWithPath: "/tmp/work"),
            mux: mux,
            validate: { _ in throw ValidatorBoom() }
        )
        let videoTemp = URL(fileURLWithPath: "/tmp/vs-video.m4s")
        let audioTemp = URL(fileURLWithPath: "/tmp/vs-audio.m4s")
        let destination = URL(fileURLWithPath: "/tmp/vs.mp4")
        let request = DownloadRequest(
            id: "vs",
            videoID: "vid",
            resolution: 1080,
            destinationURL: destination,
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("vs")
        await coordinator.handle(.completed(tempLocation: videoTemp, component: 0), taskID: "vs")
        await coordinator.handle(.completed(tempLocation: audioTemp, component: 1), taskID: "vs")

        let task = await coordinator.task("vs")
        XCTAssertEqual(task?.state.status, .failed)
        XCTAssertEqual(task?.state.error, .validationFailed)
        // The published mux product is discarded along with both component temps.
        XCTAssertEqual(Set(recorder.removedURLs), Set([videoTemp, audioTemp, destination]))
    }

    func testPassingValidatorCompletesAdaptivePath() async {
        let recorder = SeamFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, output in output }
        let coordinator = DownloadCoordinator(
            transport: SeamNoopTransport(),
            fileManager: SeamRecordingFileManager(recorder: recorder),
            directory: URL(fileURLWithPath: "/tmp/work"),
            mux: mux,
            validate: { _ in }
        )
        let request = DownloadRequest(
            id: "vp",
            videoID: "vid",
            resolution: 1080,
            destinationURL: URL(fileURLWithPath: "/tmp/vp.mp4"),
            components: [
                DownloadComponent(streamID: "v", sourceURL: URL(string: "https://example.com/v")!),
                DownloadComponent(streamID: "a", sourceURL: URL(string: "https://example.com/a")!)
            ]
        )
        _ = await coordinator.enqueue(request)
        await coordinator.begin("vp")
        await coordinator.handle(
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/vp-video.m4s"), component: 0),
            taskID: "vp"
        )
        await coordinator.handle(
            .completed(tempLocation: URL(fileURLWithPath: "/tmp/vp-audio.m4s"), component: 1),
            taskID: "vp"
        )

        let task = await coordinator.task("vp")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertNil(task?.state.error)
    }
}
