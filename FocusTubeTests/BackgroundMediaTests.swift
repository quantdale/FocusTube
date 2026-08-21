import XCTest
import AVFoundation
import MediaPlayer
@testable import FocusTube
import FocusTubeCore

/// Class (reference semantics) so assertions observe mutations made through the
/// coordinator's stored target.
@MainActor
private final class SpyTarget: PlayerCommandTarget {
    var playCount = 0
    var pauseCount = 0
    var toggleCount = 0
    var seekSeconds: TimeInterval?

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func togglePlayPause() { toggleCount += 1 }
    func seek(to seconds: TimeInterval) { seekSeconds = seconds }
}

@MainActor
final class BackgroundMediaTests: XCTestCase {
    func testRemoteCommandMapping() {
        let spy = SpyTarget()
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
        let spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.handleInterruption(.began)
        XCTAssertEqual(spy.pauseCount, 1)
        coordinator.handleInterruption(.ended(shouldResume: true))
        XCTAssertEqual(spy.playCount, 1)
    }

    func testInterruptionEndedWithoutResumeDoesNotPlay() {
        let spy = SpyTarget()
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

    /// Repeated registration (TabView re-appearance) must leave exactly one
    /// handler per command on the shared center — duplicates are forbidden.
    func testRegisterRemoteCommandsIsIdempotent() async {
        let spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        let center = MPRemoteCommandCenter.shared()

        // Hermetic start: drop anything registered earlier in the process.
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)

        coordinator.registerRemoteCommands()
        coordinator.registerRemoteCommands()

        // MPRemoteCommand's handler fires when invoked with no target.
        _ = center.playCommand.send(target: nil, error: nil)
        _ = center.pauseCommand.send(target: nil, error: nil)
        _ = center.togglePlayPauseCommand.send(target: nil, error: nil)

        // Handlers forward asynchronously onto the MainActor.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              spy.playCount < 1 || spy.pauseCount < 1 || spy.toggleCount < 1 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(spy.playCount, 1)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.toggleCount, 1)
    }

    /// Polls until `condition` holds or the deadline lapses, yielding the main
    /// actor so queued notification deliveries and actor hops can run.
    private func waitFor(
        _ condition: @autoclosure () -> Bool,
        timeout seconds: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func postInterruption(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions? = nil
    ) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: type.rawValue
        ]
        if let options {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: userInfo
        )
    }

    /// Real delivery path: a posted `AVAudioSession` interruption notification
    /// must map onto pause/resume exactly like the deterministic API — began
    /// pauses, ended without `shouldResume` stays paused, ended with
    /// `shouldResume` resumes.
    func testInterruptionNotificationsDrivePauseAndResume() async {
        let spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.registerInterruptionObservation()

        postInterruption(type: .began)
        await waitFor(spy.pauseCount == 1)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 0)

        // Ended without the shouldResume option must not restart playback.
        postInterruption(type: .ended)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 0)

        postInterruption(type: .ended, options: .shouldResume)
        await waitFor(spy.playCount == 1)
        XCTAssertEqual(spy.pauseCount, 1)
        XCTAssertEqual(spy.playCount, 1)
    }

    /// Remove-before-add re-registration must not stack observers: one posted
    /// interruption yields exactly one delivery.
    func testRegisterInterruptionObservationIsIdempotent() async {
        let spy = SpyTarget()
        let coordinator = BackgroundMediaCoordinator(target: spy)
        coordinator.registerInterruptionObservation()
        coordinator.registerInterruptionObservation()

        postInterruption(type: .began)
        await waitFor(spy.pauseCount == 1)
        // Settle window so a duplicate delivery (if any) lands before asserting.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(spy.pauseCount, 1)
    }
}
