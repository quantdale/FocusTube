import XCTest
@testable import FocusTubeCore

struct FakeMediaExtractor: MediaExtracting {
    var result: ResolvedMedia
    var error: ExtractionError?

    func resolve(videoID: String) async throws -> ResolvedMedia {
        if let error { throw error }
        return result
    }
}

final class MediaExtractionTests: XCTestCase {
    func makeStream(id: String, resolution: Int?, kind: StreamKind, nativePlayable: Bool = true) -> MediaStream {
        MediaStream(
            id: id,
            videoID: "abc",
            resolution: resolution,
            kind: kind,
            nativePlayable: nativePlayable,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: URL(string: "https://example.com/\(id)")!,
            expiresAt: nil
        )
    }

    func testDisallowedResolutionsAreFiltered() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [
                makeStream(id: "c360", resolution: 360, kind: .combined),
                makeStream(id: "c720", resolution: 720, kind: .combined),
                makeStream(id: "c1080", resolution: 1080, kind: .combined),
                makeStream(id: "c1440", resolution: 1440, kind: .combined),
                makeStream(id: "c2160", resolution: 2160, kind: .combined)
            ],
            videoOnly: [
                makeStream(id: "v480", resolution: 480, kind: .videoOnly),
                makeStream(id: "v3072", resolution: 3072, kind: .videoOnly)
            ],
            audioOnly: [
                makeStream(id: "a1", resolution: nil, kind: .audioOnly)
            ]
        )

        let filtered = MediaStreamFilter.filter(media)

        XCTAssertEqual(Set(filtered.combined.map { $0.resolution }), [360, 720, 1080])
        XCTAssertEqual(filtered.videoOnly.map { $0.resolution }, [480])
        XCTAssertEqual(filtered.audioOnly.count, 1)
    }

    func testSelectOnlineStreamPicksHighestAllowedNativeCombined() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [
                makeStream(id: "c360", resolution: 360, kind: .combined),
                makeStream(id: "c720", resolution: 720, kind: .combined),
                makeStream(id: "c1080x", resolution: 1080, kind: .combined, nativePlayable: false),
                makeStream(id: "c1080n", resolution: 1080, kind: .combined, nativePlayable: true)
            ],
            videoOnly: [],
            audioOnly: []
        )

        let selected = MediaStreamFilter.selectOnlineStream(media)

        XCTAssertEqual(selected?.id, "c1080n")
        XCTAssertLessThanOrEqual(selected?.resolution ?? 0, 1080)
    }

    func testSelectOnlineStreamNeverExceeds1080() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [
                makeStream(id: "c2160", resolution: 2160, kind: .combined),
                makeStream(id: "c1440", resolution: 1440, kind: .combined)
            ],
            videoOnly: [],
            audioOnly: []
        )

        XCTAssertNil(MediaStreamFilter.selectOnlineStream(media))
    }

    func testFakeExtractorThrowsTypedError() async {
        let extractor = FakeMediaExtractor(
            result: ResolvedMedia(videoID: "x", extractedAt: Date(), combined: [], videoOnly: [], audioOnly: []),
            error: .unavailable
        )

        do {
            _ = try await extractor.resolve(videoID: "x")
            XCTFail("expected thrown error")
        } catch let error as ExtractionError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
