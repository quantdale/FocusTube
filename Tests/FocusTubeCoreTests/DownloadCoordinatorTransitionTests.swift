import XCTest
@testable import FocusTubeCore

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// In-memory FileManaging fake: staged files exist with non-zero size so the
/// single-component completion path settles deterministically without touching
/// the host filesystem.
private struct InMemoryFileManager: FileManaging {
    var existing: Set<URL> = []

    func fileExists(at url: URL) -> Bool { existing.contains(url) }
    func size(of url: URL) -> Int64 { existing.contains(url) ? 1024 : 0 }
    func createDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt item: URL) throws {}
    func moveItem(at item: URL, to destination: URL) throws {}
    func removeItem(at url: URL) throws {}
}

/// HB-017 regression pins for coordinator event paths: status writes are legal
/// transitions, cancellation lands as the modeled cancelled failure, and a
/// settled completion can never be regressed by a late failure delivery.
final class DownloadCoordinatorTransitionTests: XCTestCase {
    private func makeRequest(id: String) -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "vid",
            streamID: "s1",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/\(id)")!,
            destinationURL: URL(fileURLWithPath: "/tmp/h3-\(id).mp4")
        )
    }

    func testLateFailureAfterCompletionDoesNotRegressSettledState() async {
        let destination = URL(fileURLWithPath: "/tmp/h3-late-fail.mp4")
        let temp = URL(fileURLWithPath: "/tmp/h3-late-fail-temp.mp4")
        // Both the staged component temp and the destination exist so the
        // single-component path validates, replaces, and settles completed.
        let files = InMemoryFileManager(existing: [destination, temp])
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: files
        )
        _ = await coordinator.enqueue(makeRequest(id: "late-fail"))
        await coordinator.begin("late-fail")

        await coordinator.handle(.completed(tempLocation: temp, component: 0), taskID: "late-fail")
        var settled = await coordinator.task("late-fail")
        XCTAssertEqual(settled?.state.status, .completed)

        // A late transport failure must NOT regress the settled completion:
        // registered playable media stays registered (HB-017).
        await coordinator.handle(.failed(.transportFailed), taskID: "late-fail")
        settled = await coordinator.task("late-fail")
        XCTAssertEqual(settled?.state.status, .completed)
        XCTAssertNil(settled?.state.error)
    }

    func testCancelFromDownloadingLandsModeledCancelledFailure() async {
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: InMemoryFileManager()
        )
        _ = await coordinator.enqueue(makeRequest(id: "cancel-me"))
        await coordinator.begin("cancel-me")

        await coordinator.cancel("cancel-me")
        let settled = await coordinator.task("cancel-me")
        XCTAssertEqual(settled?.state.status, .failed)
        XCTAssertEqual(settled?.state.error, .cancelled)
    }

    func testFailureEventUsesLegalTransitionFromDownloadingState() async {
        let coordinator = DownloadCoordinator(
            transport: NoopTransport(),
            fileManager: InMemoryFileManager()
        )
        _ = await coordinator.enqueue(makeRequest(id: "fail-me"))
        await coordinator.begin("fail-me")

        await coordinator.handle(.failed(.transportFailed), taskID: "fail-me")
        let settled = await coordinator.task("fail-me")
        XCTAssertEqual(settled?.state.status, .failed)
        XCTAssertEqual(settled?.state.error, .transportFailed)
    }
}
