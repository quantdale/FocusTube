import XCTest
@testable import FocusTube
import FocusTubeCore

/// Records commands and lets tests deliver bridge messages, driving the real
/// core `IFramePlayerController` (ADR-0007).
@MainActor
final class FakePlayerEngine: PlayerEngine {
    var controller = IFramePlayerController()
    var sent: [IFramePlayerCommand] = []
    var onStateChange: (@MainActor (IFramePlayerState) -> Void)?
    var state: IFramePlayerState { controller.state }

    func load(_ videoID: YouTubeVideoID, startSeconds: Double, autoplay: Bool) {
        run(controller.handle(.load(videoID, startSeconds: startSeconds, autoplay: autoplay)))
    }
    func play() { run(controller.handle(.play)) }
    func pause() { run(controller.handle(.pause)) }
    func seek(to seconds: Double) { run(controller.handle(.seek(seconds))) }
    func setPlaybackRate(_ rate: Double) { run(controller.handle(.setRate(rate))) }
    func stop() { run(controller.handle(.stop)) }

    func deliver(_ message: IFrameBridgeMessage) { run(controller.apply(message)) }
    private func run(_ commands: [IFramePlayerCommand]) {
        sent += commands
        onStateChange?(controller.state)
    }
}

@MainActor
final class PlayerCoordinatorTests: XCTestCase {
    let vid = "dQw4w9WgXcQ"
    var id: YouTubeVideoID { YouTubeVideoID(vid)! }

    func testLoadDefersUntilReadyThenPlays() async {
        let engine = FakePlayerEngine()
        let c = PlayerCoordinator(engine: engine)
        await c.loadAndPlay(videoID: vid, resumeAt: 42)
        XCTAssertEqual(c.state.status, .loading)
        XCTAssertEqual(engine.sent, [])
        engine.deliver(.ready)
        XCTAssertEqual(engine.sent, [.load(id, startSeconds: 42)])
        engine.deliver(.stateChange(.playing))
        XCTAssertEqual(c.state.status, .playing)
        XCTAssertEqual(c.currentVideoID, vid)
    }

    func testTinyResumeStartsAtZero() async {
        let engine = FakePlayerEngine()
        engine.deliver(.ready)
        let c = PlayerCoordinator(engine: engine)
        await c.loadAndPlay(videoID: vid, resumeAt: 0.2)
        XCTAssertEqual(engine.sent.last, .load(id, startSeconds: 0))
    }

    func testInvalidIDFailsWithoutTouchingEngine() async {
        let engine = FakePlayerEngine()
        let c = PlayerCoordinator(engine: engine)
        await c.loadAndPlay(videoID: "bad'); x(")
        XCTAssertEqual(c.state.status, .failed)
        XCTAssertEqual(c.state.error, .noPlayableStream)
        XCTAssertNil(engine.state.videoID)
    }

    func testEmbeddingDisabledSurfacesTypedError() async {
        let engine = FakePlayerEngine()
        engine.deliver(.ready)
        let c = PlayerCoordinator(engine: engine)
        await c.loadAndPlay(videoID: vid)
        engine.deliver(.error(.embeddingNotAllowed))
        XCTAssertEqual(c.state.status, .failed)
        XCTAssertEqual(c.state.error, .noPlayableStream)
        XCTAssertEqual(c.iframeError, .embeddingNotAllowed)
    }

    func testProgressIsThrottledAndFlushedOnPause() async {
        let engine = FakePlayerEngine()
        engine.deliver(.ready)
        let c = PlayerCoordinator(engine: engine)
        var reported: [TimeInterval] = []
        c.onProgress = { reported.append($0) }
        await c.loadAndPlay(videoID: vid)
        engine.deliver(.stateChange(.playing))
        for t in stride(from: 0.5, through: 11, by: 0.5) {
            engine.deliver(.progress(currentTime: t, duration: 100))
        }
        XCTAssertEqual(reported, [0.5, 5.5, 10.5])
        engine.deliver(.progress(currentTime: 11.5, duration: 100))
        engine.deliver(.stateChange(.paused))
        XCTAssertEqual(reported.last, 11.5)
    }

    func testCommandTargetAndStop() async {
        let engine = FakePlayerEngine()
        engine.deliver(.ready)
        let c = PlayerCoordinator(engine: engine)
        var nowPlayingCalls = 0
        c.onNowPlayingChanged = { nowPlayingCalls += 1 }
        await c.loadAndPlay(videoID: vid)
        engine.deliver(.stateChange(.playing))
        engine.deliver(.progress(currentTime: 30, duration: 100))
        XCTAssertEqual(c.nowPlayingSnapshot.currentTime, 30)
        XCTAssertEqual(c.nowPlayingSnapshot.rate, 1)
        c.togglePlayPause()
        XCTAssertEqual(engine.sent.last, .pause)
        engine.deliver(.stateChange(.paused))
        XCTAssertEqual(c.nowPlayingSnapshot.rate, 0)
        c.seek(to: 50)
        XCTAssertEqual(engine.sent.last, .seek(seconds: 50))
        c.stop()
        XCTAssertEqual(engine.sent.last, .stop)
        XCTAssertEqual(c.state.status, .idle)
        XCTAssertNil(c.currentVideoID)
        XCTAssertGreaterThan(nowPlayingCalls, 0)
        engine.deliver(.stateChange(.playing))
        XCTAssertEqual(c.state.status, .idle, "late events after stop must not revive playback")
    }

    func testFixtureEngineReachesPlaying() async throws {
        let c = PlayerCoordinator(engine: FixturePlayerEngine(), resolveID: FixturePlayerEngine.resolveFixtureID)
        await c.loadAndPlay(videoID: "fix-home-1")
        for _ in 0..<40 where c.state.status != .playing {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(c.state.status, .playing)
    }
}
