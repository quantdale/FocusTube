import XCTest
@testable import FocusTubeCore

final class PlaybackStateTests: XCTestCase {
    func testValidTransitions() throws {
        var state = PlaybackState()
        XCTAssertEqual(state.status, .idle)

        try state.transition(to: .loading)
        try state.transition(to: .ready)
        try state.transition(to: .playing)
        try state.transition(to: .paused)
        try state.transition(to: .playing)
        try state.transition(to: .failed)

        XCTAssertEqual(state.status, .failed)
    }

    func testFailedStateClearsOnRecovery() throws {
        var state = PlaybackState()
        try state.transition(to: .loading)
        try state.transition(to: .failed)
        try state.transition(to: .idle)
        XCTAssertNil(state.error)
    }

    func testInvalidTransitionThrows() {
        var state = PlaybackState()
        XCTAssertThrowsError(try state.transition(to: .playing)) { error in
            XCTAssertEqual(error as? PlaybackState.TransitionError, .invalidTransition)
        }
    }

    func testSelectionWithoutPlayableStreamIsNil() {
        let media = ResolvedMedia(
            videoID: "x",
            extractedAt: Date(),
            combined: [
                MediaStream(
                    id: "u", videoID: "x", resolution: 2160, kind: .combined,
                    nativePlayable: true, container: "mp4", videoCodec: "avc1",
                    audioCodec: "mp4a", sourceURL: URL(string: "https://e/u")!, expiresAt: nil
                )
            ],
            videoOnly: [],
            audioOnly: []
        )
        XCTAssertNil(MediaStreamFilter.selectOnlineStream(media))
    }
}
