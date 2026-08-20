import XCTest
@testable import FocusTubeCore

final class DownloadPlannerTests: XCTestCase {
    func makeStream(id: String, resolution: Int?, kind: StreamKind, nativePlayable: Bool = true) -> MediaStream {
        MediaStream(
            id: id,
            videoID: "v",
            resolution: resolution,
            kind: kind,
            nativePlayable: nativePlayable,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: URL(string: "https://e/\(id)")!,
            expiresAt: nil
        )
    }

    func testExactCombined1080ChosenDirectly() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(id: "c1080", resolution: 1080, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        guard case let .combined(component, resolution) = plan else {
            XCTFail("Expected combined 1080 plan, got \(plan)")
            return
        }
        XCTAssertEqual(resolution, 1080)
        XCTAssertEqual(component.sourceURL.absoluteString, "https://e/c1080")
    }

    func testAdaptive1080ChosenWhenCombinedMissing() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(id: "v1080", resolution: 1080, kind: .videoOnly)],
            audioOnly: [makeStream(id: "a", resolution: nil, kind: .audioOnly)]
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        guard case let .adaptive(video, audio, resolution) = plan else {
            XCTFail("Expected adaptive 1080 plan, got \(plan)")
            return
        }
        XCTAssertEqual(resolution, 1080)
        XCTAssertEqual(video.sourceURL.absoluteString, "https://e/v1080")
        XCTAssertEqual(audio.sourceURL.absoluteString, "https://e/a")
    }

    func testRequested1080NeverFallsBackTo720() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(id: "c720", resolution: 720, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        guard case let .unavailable(reason) = plan else {
            XCTFail("Expected unavailable 1080, got \(plan)")
            return
        }
        XCTAssertEqual(reason, .requestedQualityUnavailable)
    }

    func test1080CeilingRejectsOnlyHigherSource() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(id: "c2160", resolution: 2160, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        XCTAssertEqual(plan, .unavailable(reason: .requestedQualityUnavailable))
    }

    func testExactCombined720ChosenFor720Request() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(id: "c720", resolution: 720, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p720)
        XCTAssertEqual(plan, .combined(DownloadComponent(streamID: "c720", sourceURL: URL(string: "https://e/c720")!), resolution: 720))
    }

    func testAdaptive720NotSilentlyDowngradedFrom1080() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(id: "v720", resolution: 720, kind: .videoOnly)],
            audioOnly: [makeStream(id: "a", resolution: nil, kind: .audioOnly)]
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        XCTAssertEqual(plan, .unavailable(reason: .requestedQualityUnavailable))
    }

    func testNoAllowedStreamReportedWhenNothingDownloadable() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        XCTAssertEqual(plan, .unavailable(reason: .noAllowedStream))
    }
}
