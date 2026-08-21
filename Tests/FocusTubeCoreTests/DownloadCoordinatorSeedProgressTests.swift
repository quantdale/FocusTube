import Foundation
import Testing
@testable import FocusTubeCore

private struct SeedTestsTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Coverage for relaunch progress seeding (HB-002): a freshly reattached task
/// must expose the persisted cumulative bytes instead of restarting at zero.
@Test func seedProgressPopulatesCumulativeBytes() async {
    let coordinator = DownloadCoordinator(transport: SeedTestsTransport())
    let request = DownloadRequest(
        id: "seed-1",
        videoID: "v1",
        resolution: 720,
        destinationURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("seed-1.mp4"),
        components: []
    )
    _ = await coordinator.enqueue(request)

    await coordinator.seedProgress(taskID: "seed-1", bytesDownloaded: 4_000, totalBytes: 10_000)
    let task = await coordinator.task("seed-1")
    #expect(task?.state.bytesDownloaded == 4_000)
    #expect(task?.state.totalBytes == 10_000)
}

@Test func seedProgressIgnoresUnknownTask() async {
    let coordinator = DownloadCoordinator(transport: SeedTestsTransport())
    // Must be a silent no-op, not a crash or state corruption.
    await coordinator.seedProgress(taskID: "missing", bytesDownloaded: 1, totalBytes: 2)
    let task = await coordinator.task("missing")
    #expect(task == nil)
}
