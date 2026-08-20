import XCTest
import MediaPlayer
@testable import FocusTube
import FocusTubeCore

private struct SpyTarget: PlayerCommandTarget {
    var playCount = 0
    var pauseCount = 0
    var toggleCount = 0
    var seekSeconds: TimeInterval?

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func togglePlayPause() { toggleCount += 1 }
    func seek(to seconds: TimeInterval) { seekSeconds = seconds }
}

final class BackgroundMediaTests: XCTestCase {
    func testRemoteCommandMapping() {
        var spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.handleRemoteCommand(.play)
        coordinator.handleRemoteCommand(.pause)
        coordinator.handleRemoteCommand(.togglePlayPause)
        coordinator.handleRemoteCommand(.seek(42))
        XCTAssertEqual(spy.playCount, 1)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.toggleCount, 1)
        XCTAssertEqual(spy.seekSeconds, 42)
    }

    func testInterruptionBeganPausesAndResumesWhenAllowed() {
        var spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.handleInterruption(.began)
        XCTAssertEqual(spy.pauseCount, 1)
        coordinator.handleInterruption(.ended(shouldResume: true))
        XCTAssertEqual(spy.playCount, 1)
    }

    func testInterruptionEndedWithoutResumeDoesNotPlay() {
        var spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.handleInterruption(.ended(shouldResume: false))
        XCTAssertEqual(spy.playCount, 0)
        XCTAssertEqual(spy.pauseCount, 0)
    }

    func testNowPlayingInfoContent() {
        let info = NowPlayingInfoBuilder.info(title: "My Title", artist: "My Channel", duration: 120, currentTime: 30)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "My Title")
        XCTAssertEqual(info[MPMediaItemPropertyArtist] as? String, "My Channel")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? TimeInterval, 120)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval, 30)
    }

    func testAudioSessionPolicyIsPlayback() {
        XCTAssertEqual(BackgroundMediaPolicy.audioSessionCategory, .playback)
        XCTAssertEqual(BackgroundMediaPolicy.audioSessionMode, .moviePlayback)
    }
}
