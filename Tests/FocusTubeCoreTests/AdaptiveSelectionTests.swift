import XCTest
@testable import FocusTubeCore

final class AdaptiveSelectionTests: XCTestCase {
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

    func testSelects1080VideoAndAudio() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [],
            videoOnly: [
                makeStream(id: "v720", resolution: 720, kind: .videoOnly),
                makeStream(id: "v1080", resolution: 1080, kind: .videoOnly)
            ],
            audioOnly: [makeStream(id: "a1", resolution: nil, kind: .audioOnly)]
        )

        let components = AdaptiveSelection.select1080(media)
        XCTAssertEqual(components?.video.id, "v1080")
        XCTAssertEqual(components?.audio.id, "a1")
    }

    func testNilWhenNoAudio() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(id: "v1080", resolution: 1080, kind: .videoOnly)],
            audioOnly: []
        )
        XCTAssertNil(AdaptiveSelection.select1080(media))
    }

    func testNilWhenNoVideo() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [],
            videoOnly: [],
            audioOnly: [makeStream(id: "a1", resolution: nil, kind: .audioOnly)]
        )
        XCTAssertNil(AdaptiveSelection.select1080(media))
    }

    func testNeverExceeds1080() {
        let media = ResolvedMedia(
            videoID: "abc",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(id: "v1440", resolution: 1440, kind: .videoOnly)],
            audioOnly: [makeStream(id: "a1", resolution: nil, kind: .audioOnly)]
        )
        XCTAssertNil(AdaptiveSelection.select1080(media))
    }
}
