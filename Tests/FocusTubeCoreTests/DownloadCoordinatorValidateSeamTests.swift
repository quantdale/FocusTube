import XCTest
@testable import FocusTubeCore

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
        let recorder = TempFileRecorder()
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
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
        let recorder = TempFileRecorder()
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
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
        let recorder = TempFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, output in output }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
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
        let recorder = TempFileRecorder()
        let mux: @Sendable ([URL], URL) async throws -> URL = { _, output in output }
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: RecordingFileManager(recorder: recorder),
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
