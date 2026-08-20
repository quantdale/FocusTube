import XCTest
@testable import FocusTube
import FocusTubeCore

/// Opt-in live playback smoke: runs only when FOCUSTUBE_LIVE_SMOKE=1 is set.
/// Exercises the full native online-playback path (extraction -> selection ->
/// AVPlayer) against a representative long-form source. Kept separate from the
/// deterministic merge gates so normal CI does not depend on live YouTube.
final class PlaybackStartSmoke: XCTestCase {
    func testOnlinePlaybackStarts() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FOCUSTUBE_LIVE_SMOKE"] != "1",
            "Opt-in live playback smoke; set FOCUSTUBE_LIVE_SMOKE=1 to run against YouTube."
        )

        let coordinator = await PlayerCoordinator()
        await coordinator.loadAndPlay(videoID: "aqz-KE-bpKQ")

        let reachedPlayable = await waitForPlayable(coordinator: coordinator, timeout: 45)
        XCTAssertTrue(
            reachedPlayable,
            "Expected native online playback to reach ready/playing state for long-form sample"
        )
    }

    private func waitForPlayable(coordinator: PlayerCoordinator, timeout seconds: Int) async -> Bool {
        for _ in 0..<seconds {
            let status = await coordinator.state.status
            if status == .ready || status == .playing {
                return true
            }
            if status == .failed {
                return false
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }
}
