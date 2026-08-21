import XCTest
@testable import FocusTube
import FocusTubeCore
import AVFoundation

private struct FakeMediaExtractor: MediaExtracting {
    var result: ResolvedMedia
    var error: ExtractionError?

    func resolve(videoID: String) async throws -> ResolvedMedia {
        if let error { throw error }
        return result
    }
}

@MainActor
final class PlayerCoordinatorTests: XCTestCase {
    func makeStream(id: String, resolution: Int?, kind: StreamKind, nativePlayable: Bool = true, url: URL) -> MediaStream {
        MediaStream(
            id: id,
            videoID: "abc",
            resolution: resolution,
            kind: kind,
            nativePlayable: nativePlayable,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: url,
            expiresAt: nil
        )
    }

    func testSelectOnlineStreamDelegatesToPolicy() async {
        let coordinator = await PlayerCoordinator()
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [
                makeStream(id: "c360", resolution: 360, kind: .combined, url: URL(string: "https://e/360")!),
                makeStream(id: "c1080n", resolution: 1080, kind: .combined, nativePlayable: true, url: URL(string: "https://e/1080n")!),
                makeStream(id: "c1080x", resolution: 1080, kind: .combined, nativePlayable: false, url: URL(string: "https://e/1080x")!)
            ],
            videoOnly: [],
            audioOnly: []
        )

        let selected = await coordinator.selectOnlineStream(from: media)
        XCTAssertEqual(selected?.id, "c1080n")
    }

    func testPrepareCreatesAVPlayerItemForSelectedStream() async {
        let coordinator = await PlayerCoordinator()
        let url = URL(fileURLWithPath: "/tmp/focustube-sample.mp4")
        let stream = makeStream(id: "c720", resolution: 720, kind: .combined, url: url)

        await coordinator.prepare(stream: stream)

        XCTAssertEqual(coordinator.currentStream?.id, "c720")
        // A local file can already have reached .ready via KVO by the time we
        // assert; only the transient states are wrong here.
        XCTAssertTrue(
            coordinator.state.status == .loading || coordinator.state.status == .ready,
            "unexpected status: \(coordinator.state.status)"
        )
        XCTAssertEqual((coordinator.player.currentItem?.asset as? AVURLAsset)?.url, url)
    }

    func testPlaybackErrorMapping() {
        XCTAssertEqual(PlayerCoordinator.playbackError(for: .failed), .itemFailed)
        XCTAssertEqual(PlayerCoordinator.playbackError(for: .readyToPlay), .unknown)
    }

    func testNoPlayableStreamYieldsTypedFailure() async {
        let extractor = FakeMediaExtractor(
            result: ResolvedMedia(
                videoID: "x",
                extractedAt: Date(),
                combined: [makeStream(id: "c2160", resolution: 2160, kind: .combined, url: URL(string: "https://e/2160")!)],
                videoOnly: [],
                audioOnly: []
            ),
            error: nil
        )
        let coordinator = await PlayerCoordinator(extractor: extractor)

        await coordinator.loadAndPlay(videoID: "x")

        XCTAssertEqual(coordinator.state.status, .failed)
        XCTAssertEqual(coordinator.state.error, .noPlayableStream)
    }

    func testExtractionErrorYieldsTypedFailure() async {
        let extractor = FakeMediaExtractor(
            result: ResolvedMedia(videoID: "x", extractedAt: Date(), combined: [], videoOnly: [], audioOnly: []),
            error: .unavailable
        )
        let coordinator = await PlayerCoordinator(extractor: extractor)

        await coordinator.loadAndPlay(videoID: "x")

        XCTAssertEqual(coordinator.state.status, .failed)
    }
}
