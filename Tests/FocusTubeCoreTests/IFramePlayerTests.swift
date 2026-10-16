import XCTest
@testable import FocusTubeCore

final class IFramePlayerTests: XCTestCase {
    let id = YouTubeVideoID("dQw4w9WgXcQ")!

    func testVideoIDValidation() {
        XCTAssertNotNil(YouTubeVideoID("abc_DEF-123"))
        XCTAssertNil(YouTubeVideoID("short"))
        XCTAssertNil(YouTubeVideoID("abc'DEF-123"))
        XCTAssertNil(YouTubeVideoID("abcdefghijkl"))
        XCTAssertNil(YouTubeVideoID("abc def;123"))
    }

    func testCommandJavaScript() {
        XCTAssertEqual(IFramePlayerCommand.load(id, startSeconds: 12.5).javaScript,
                       "player.loadVideoById({videoId:'dQw4w9WgXcQ',startSeconds:12.500});")
        XCTAssertEqual(IFramePlayerCommand.cue(id, startSeconds: .nan).javaScript,
                       "player.cueVideoById({videoId:'dQw4w9WgXcQ',startSeconds:0});")
        XCTAssertEqual(IFramePlayerCommand.seek(seconds: -3).javaScript, "player.seekTo(0,true);")
        XCTAssertEqual(IFramePlayerCommand.play.javaScript, "player.playVideo();")
        XCTAssertEqual(IFramePlayerCommand.setPlaybackRate(1.5).javaScript, "player.setPlaybackRate(1.500);")
    }

    func testParseMessages() throws {
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onReady"]), .ready)
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onStateChange", "data": 1]), .stateChange(.playing))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onStateChange", "data": -1.0]), .stateChange(.unstarted))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onError", "data": 150]), .error(.embeddingNotAllowed))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onError", "data": 101]), .error(.embeddingNotAllowed))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onError", "data": 7]), .error(.unknown(7)))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "onPlaybackRateChange", "data": 2.0]), .playbackRateChange(2))
        XCTAssertEqual(try IFrameBridgeMessage.parse(["event": "progress", "data": ["currentTime": 3.5, "duration": 10]]),
                       .progress(currentTime: 3.5, duration: 10))
        XCTAssertEqual(try IFrameBridgeMessage.parse(#"{"event":"onStateChange","data":2}"#), .stateChange(.paused))
    }

    func testParseRejectsMalformed() {
        func err(_ body: Any) -> IFrameBridgeMessage.ParseError? {
            do { _ = try IFrameBridgeMessage.parse(body); return nil } catch { return error }
        }
        XCTAssertEqual(err(42), .notAnObject)
        XCTAssertEqual(err("not json"), .notAnObject)
        XCTAssertEqual(err(["data": 1]), .missingEvent)
        XCTAssertEqual(err(["event": "onWhatever"]), .unknownEvent("onWhatever"))
        XCTAssertEqual(err(["event": "onStateChange", "data": 4]), .invalidData("onStateChange"))
        XCTAssertEqual(err(["event": "onStateChange", "data": 1.5]), .invalidData("onStateChange"))
        XCTAssertEqual(err(["event": "progress", "data": ["currentTime": -1, "duration": 3]]), .invalidData("progress"))
        XCTAssertEqual(err(["event": "onPlaybackRateChange", "data": 0]), .invalidData("onPlaybackRateChange"))
    }

    func testLoadBeforeReadyIsDeferredAndFlushed() {
        var c = IFramePlayerController()
        XCTAssertEqual(c.handle(.load(id, startSeconds: 5, autoplay: true)), [])
        XCTAssertEqual(c.state.phase, .loadingPlayer)
        XCTAssertEqual(c.state.legacyStatus, .loading)
        XCTAssertEqual(c.handle(.seek(10)), [])
        XCTAssertEqual(c.apply(.ready), [.load(id, startSeconds: 5)])
        XCTAssertEqual(c.state.phase, .buffering)
        XCTAssertEqual(c.apply(.ready), [], "pending load flushed only once")
    }

    func testCueThenPlayBeforeReady() {
        var c = IFramePlayerController()
        _ = c.handle(.load(id, startSeconds: 0, autoplay: false))
        XCTAssertEqual(c.handle(.play), [])
        XCTAssertEqual(c.apply(.ready), [.cue(id, startSeconds: 0), .play])
        XCTAssertEqual(c.state.phase, .cued)
    }

    func testPlaybackLifecycle() {
        var c = IFramePlayerController()
        _ = c.apply(.ready)
        XCTAssertEqual(c.state.phase, .idle)
        XCTAssertEqual(c.handle(.play), [], "no video yet")
        XCTAssertEqual(c.handle(.load(id, startSeconds: 0, autoplay: true)), [.load(id, startSeconds: 0)])
        _ = c.apply(.stateChange(.unstarted))
        XCTAssertEqual(c.state.phase, .buffering)
        _ = c.apply(.stateChange(.playing))
        XCTAssertEqual(c.state.legacyStatus, .playing)
        _ = c.apply(.progress(currentTime: 30, duration: 100))
        XCTAssertEqual(c.handle(.togglePlayPause), [.pause])
        _ = c.apply(.stateChange(.paused))
        XCTAssertEqual(c.handle(.pause), [], "already paused")
        XCTAssertEqual(c.handle(.togglePlayPause), [.play])
        XCTAssertEqual(c.handle(.skip(by: 10)), [.seek(seconds: 40)])
        XCTAssertEqual(c.handle(.seek(500)), [.seek(seconds: 100)])
        XCTAssertEqual(c.handle(.skip(by: -1000)), [.seek(seconds: 0)])
        _ = c.apply(.stateChange(.ended))
        XCTAssertEqual(c.state.phase, .ended)
        XCTAssertEqual(c.state.currentTime, 100)
        XCTAssertEqual(c.handle(.setRate(1.25)), [.setPlaybackRate(1.25)])
        _ = c.apply(.playbackRateChange(1.25))
        XCTAssertEqual(c.state.playbackRate, 1.25)
    }

    func testErrorBlocksPlayUntilReload() {
        var c = IFramePlayerController()
        _ = c.apply(.ready)
        _ = c.handle(.load(id, startSeconds: 0, autoplay: true))
        _ = c.apply(.error(.embeddingNotAllowed))
        XCTAssertEqual(c.state.phase, .failed(.embeddingNotAllowed))
        XCTAssertEqual(c.state.legacyStatus, .failed)
        XCTAssertFalse(IFramePlayerError.embeddingNotAllowed.isRetryable)
        XCTAssertEqual(c.handle(.play), [])
        XCTAssertEqual(c.handle(.load(id, startSeconds: 0, autoplay: true)).count, 1)
        XCTAssertEqual(c.state.phase, .buffering)
    }

    func testStopResetsButKeepsReadiness() {
        var c = IFramePlayerController()
        _ = c.apply(.ready)
        _ = c.handle(.load(id, startSeconds: 0, autoplay: true))
        XCTAssertEqual(c.handle(.stop), [.stop])
        XCTAssertEqual(c.state.phase, .idle)
        XCTAssertTrue(c.state.isPlayerReady)
        XCTAssertNil(c.state.videoID)
        _ = c.apply(.stateChange(.playing))
        XCTAssertEqual(c.state.phase, .idle, "stale events after stop are ignored")
    }

    func testStopBeforeReadyDropsPendingLoad() {
        var c = IFramePlayerController()
        _ = c.handle(.load(id, startSeconds: 0, autoplay: true))
        XCTAssertEqual(c.handle(.stop), [])
        XCTAssertEqual(c.apply(.ready), [])
    }

    func testEmbedPageUsesOfficialPrivacyEnhancedPlayer() {
        let html = IFrameEmbedPage.html()
        XCTAssertTrue(html.contains("https://www.youtube.com/iframe_api"))
        XCTAssertTrue(html.contains("youtube-nocookie.com"))
        XCTAssertTrue(html.contains("\"playsinline\":\"1\""))
        XCTAssertTrue(html.contains("\"enablejsapi\":\"1\""))
        XCTAssertTrue(html.contains("messageHandlers.focustube"))
        XCTAssertTrue(html.contains("\"origin\":\"https://com.quantdale.focustube\""))
    }
}
