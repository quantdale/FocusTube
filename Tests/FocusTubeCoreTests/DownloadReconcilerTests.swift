import XCTest
@testable import FocusTubeCore

final class DownloadReconcilerTests: XCTestCase {
    func makeTask(id: String, status: DownloadStatus, destination: String = "/tmp/\(UUID().uuidString).mp4") -> DownloadTask {
        DownloadTask(
            id: id,
            videoID: "v",
            streamID: "s",
            resolution: 720,
            sourceURL: URL(string: "https://e/\(id)")!,
            destinationURL: URL(fileURLWithPath: destination),
            state: DownloadState(status: status)
        )
    }

    /// Default seam: files exist with a non-zero size.
    private func reconcile(
        _ tasks: [DownloadTask],
        fileExists: @escaping (URL) -> Bool = { _ in true },
        sizeOf: @escaping (URL) -> Int64 = { _ in 1024 }
    ) -> [DownloadTask] {
        DownloadReconciler.reconcile(tasks, fileExists: fileExists, sizeOf: sizeOf)
    }

    func testDownloadingBecomesInterrupted() {
        let tasks = [makeTask(id: "a", status: .downloading)]
        let reconciled = reconcile(tasks, fileExists: { _ in true })
        XCTAssertEqual(reconciled.first?.state.status, .failed)
        XCTAssertEqual(reconciled.first?.state.error, .interrupted)
    }

    func testFinalizingBecomesInterrupted() {
        let tasks = [makeTask(id: "a", status: .finalizing)]
        let reconciled = reconcile(tasks, fileExists: { _ in true })
        XCTAssertEqual(reconciled.first?.state.error, .interrupted)
    }

    func testCompletedMissingFileBecomesValidationFailure() {
        let tasks = [makeTask(id: "a", status: .completed)]
        let reconciled = reconcile(tasks, fileExists: { _ in false })
        XCTAssertEqual(reconciled.first?.state.status, .failed)
        XCTAssertEqual(reconciled.first?.state.error, .validationFailed)
    }

    func testCompletedWithFileStaysCompleted() {
        let tasks = [makeTask(id: "a", status: .completed)]
        let reconciled = reconcile(tasks)
        XCTAssertEqual(reconciled.first?.state.status, .completed)
    }

    func testCompletedZeroByteFileBecomesValidationFailure() {
        // Finalization requires existence AND size > 0; reconciliation must
        // not settle a truncated/zero-byte final as playable.
        let tasks = [makeTask(id: "a", status: .completed)]
        let reconciled = reconcile(tasks, sizeOf: { _ in 0 })
        XCTAssertEqual(reconciled.first?.state.status, .failed)
        XCTAssertEqual(reconciled.first?.state.error, .validationFailed)
    }

    func testQueuedAndPausedUnchanged() {
        let tasks = [
            makeTask(id: "a", status: .queued),
            makeTask(id: "b", status: .paused)
        ]
        let reconciled = reconcile(tasks, fileExists: { _ in false })
        XCTAssertEqual(reconciled[0].state.status, .queued)
        XCTAssertEqual(reconciled[1].state.status, .paused)
    }
}
