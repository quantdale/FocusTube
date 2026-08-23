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

    // MARK: - Resume seek + stale selection (RELEASE_CONFIDENCE_V1)

    /// Extraction seam that parks ONLY the gated video's resolution on a
    /// deterministic gate; other videos resolve immediately. Lets a stale-
    /// selection race be driven without sleeps.
    @MainActor
    private final class GatedExtractor: MediaExtracting, @unchecked Sendable {
        private let gateVideoID: String
        private var continuation: CheckedContinuation<ResolvedMedia, Never>?
        private(set) var isWaiting = false

        init(gateVideoID: String) {
            self.gateVideoID = gateVideoID
        }

        func resolve(videoID: String) async throws -> ResolvedMedia {
            guard videoID == gateVideoID else {
                return ResolvedMedia(
                    videoID: videoID,
                    extractedAt: Date(),
                    combined: [Self.stream(id: "c720-\(videoID)", videoID: videoID)],
                    videoOnly: [],
                    audioOnly: []
                )
            }
            isWaiting = true
            defer { isWaiting = false }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release(_ media: ResolvedMedia) {
            continuation?.resume(returning: media)
        }

        static func stream(id: String, videoID: String) -> MediaStream {
            MediaStream(
                id: id,
                videoID: videoID,
                resolution: 720,
                kind: .combined,
                nativePlayable: true,
                container: "mp4",
                videoCodec: "avc1",
                audioCodec: "mp4a",
                sourceURL: URL(string: "https://e/\(videoID)")!,
                expiresAt: nil
            )
        }
    }

    private func media(videoID: String) -> ResolvedMedia {
        ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: [makeStream(id: "c720-\(videoID)", resolution: 720, kind: .combined, url: URL(string: "https://e/\(videoID)")!)],
            videoOnly: [],
            audioOnly: []
        )
    }

    func testResumeSeekConsumedExactlyOnceOnReady() async throws {
        let coordinator = await PlayerCoordinator(extractor: FakeMediaExtractor(result: media(videoID: "abc"), error: nil))
        var seeks: [TimeInterval] = []
        coordinator.seekAction = { seeks.append($0) }

        await coordinator.loadAndPlay(videoID: "abc", resumeAt: 42)
        XCTAssertEqual(coordinator.pendingResumeSeek, 42)
        XCTAssertTrue(seeks.isEmpty, "no seek before the item reports ready")

        coordinator.handle(itemStatus: .readyToPlay)
        XCTAssertEqual(seeks, [42])
        XCTAssertNil(coordinator.pendingResumeSeek)

        // A duplicate ready delivery must not re-seek.
        coordinator.handle(itemStatus: .readyToPlay)
        XCTAssertEqual(seeks, [42], "resume seek must be consumed exactly once")
    }

    func testTinyResumePositionsSkipTheSeek() async throws {
        let coordinator = await PlayerCoordinator(extractor: FakeMediaExtractor(result: media(videoID: "abc"), error: nil))
        var seeks: [TimeInterval] = []
        coordinator.seekAction = { seeks.append($0) }

        await coordinator.loadAndPlay(videoID: "abc", resumeAt: 0.2)
        coordinator.handle(itemStatus: .readyToPlay)
        XCTAssertTrue(seeks.isEmpty, "sub-half-second positions must not trigger a pointless seek")
        XCTAssertNil(coordinator.pendingResumeSeek)
    }

    func testStopAndLocalPlaybackClearPendingResume() async throws {
        let coordinator = await PlayerCoordinator(extractor: FakeMediaExtractor(result: media(videoID: "abc"), error: nil))

        await coordinator.loadAndPlay(videoID: "abc", resumeAt: 30)
        XCTAssertEqual(coordinator.pendingResumeSeek, 30)
        coordinator.stop()
        XCTAssertNil(coordinator.pendingResumeSeek)

        await coordinator.loadAndPlay(videoID: "abc", resumeAt: 30)
        coordinator.playLocalFile(URL(fileURLWithPath: "/tmp/local.mp4"), title: "local")
        XCTAssertNil(coordinator.pendingResumeSeek, "local playback must not inherit the previous selection's resume target")
    }

    func testFailedExtractionClearsPendingResume() async throws {
        let extractor = FakeMediaExtractor(
            result: ResolvedMedia(videoID: "x", extractedAt: Date(), combined: [], videoOnly: [], audioOnly: []),
            error: .unavailable
        )
        let coordinator = await PlayerCoordinator(extractor: extractor)

        await coordinator.loadAndPlay(videoID: "x", resumeAt: 42)
        XCTAssertEqual(coordinator.state.status, .failed)
        XCTAssertNil(coordinator.pendingResumeSeek)
    }

    func testLateFirstSelectionCannotClobberNewerSelection() async throws {
        let extractor = GatedExtractor(gateVideoID: "A")
        let coordinator = await PlayerCoordinator(extractor: extractor)

        // A starts extracting and parks on the gate...
        let taskA = Task { await coordinator.loadAndPlay(videoID: "A") }
        var spins = 0
        while !extractor.isWaiting {
            spins += 1
            if spins > 10_000 {
                XCTFail("gated extraction for A never parked; harness deadlock")
                extractor.release(GatedExtractor.stream(id: "c720-A", videoID: "A"))
                await taskA.value
                return
            }
            await Task.yield()
        }

        // ...B resolves immediately and becomes current.
        await coordinator.loadAndPlay(videoID: "B")
        XCTAssertEqual(coordinator.currentVideoID, "B")

        // A's late result arrives; the generation guard must discard it.
        extractor.release(GatedExtractor.stream(id: "c720-A", videoID: "A"))
        await taskA.value
        XCTAssertEqual(coordinator.currentVideoID, "B", "a late extraction for A must never replace B")
        XCTAssertEqual(coordinator.currentStream?.id, "c720-B")
    }
}
