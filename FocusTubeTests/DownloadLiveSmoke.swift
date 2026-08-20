import XCTest
@testable import FocusTube
import FocusTubeCore

/// Opt-in live combined-download + offline-playback smoke. Runs only when
/// FOCUSTUBE_LIVE_SMOKE=1. Resolves a real long-form video, selects an allowed
/// combined stream, downloads it through the URLSession transport, validates the
/// finalized file, then proves offline native playback from the local file.
final class DownloadLiveSmoke: XCTestCase {
    func testCombinedDownloadThenOfflinePlayback() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FOCUSTUBE_LIVE_SMOKE"] != "1",
            "Opt-in live download smoke; set FOCUSTUBE_LIVE_SMOKE=1 to run against YouTube."
        )

        let resolved = try await YouTubeKitMediaExtractor().resolve(videoID: "aqz-KE-bpKQ")
        guard let stream = MediaStreamFilter.selectOnlineStream(resolved) else {
            XCTFail("No allowed native combined stream for live sample")
            return
        }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-live-\(stream.id).mp4")
        try? FileManager.default.removeItem(at: destination)

        let request = DownloadRequest(
            id: "live-d1",
            videoID: stream.videoID,
            streamID: stream.id,
            resolution: stream.resolution ?? 720,
            sourceURL: stream.sourceURL,
            destinationURL: destination
        )

        let coordinator = DownloadCoordinator(transport: URLSessionDownloadTransport())
        _ = await coordinator.enqueue(request)
        await coordinator.begin("live-d1")

        let completed = await waitForCompletion(coordinator: coordinator, timeout: 120)
        XCTAssertTrue(completed, "Expected combined download to finalize and validate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        let player = await PlayerCoordinator()
        await player.playLocalFile(destination)
        let reachable = await player.state.status == .loading || await player.state.status == .ready || await player.state.status == .playing
        XCTAssertTrue(reachable, "Offline player item should be loaded from the local file")
    }

    private func waitForCompletion(coordinator: DownloadCoordinator, timeout seconds: Int) async -> Bool {
        for _ in 0..<seconds {
            if let task = await coordinator.task("live-d1"), task.state.status == .completed {
                return true
            }
            if let task = await coordinator.task("live-d1"), task.state.status == .failed {
                return false
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }
}
