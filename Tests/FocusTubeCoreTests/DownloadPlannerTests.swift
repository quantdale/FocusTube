import XCTest
@testable import FocusTubeCore

final class DownloadPlannerTests: XCTestCase {
    func makeStream(resolution: Int?, kind: StreamKind, nativePlayable: Bool = true) -> MediaStream {
        let id = "\(resolution.map(String.init) ?? "audio")-\(kind)"
        return MediaStream(
            id: id,
            videoID: "v",
            resolution: resolution,
            kind: kind,
            nativePlayable: nativePlayable,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: URL(string: "https://e/\(resolution.map(String.init) ?? "audio")")!,
            expiresAt: nil
        )
    }

    func testExactCombined1080ChosenDirectly() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(resolution: 1080, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        guard case let .combined(component, resolution) = plan else {
            XCTFail("Expected combined 1080 plan, got \(plan)")
            return
        }
        XCTAssertEqual(resolution, 1080)
        XCTAssertEqual(component.sourceURL.absoluteString, "https://e/1080")
        XCTAssertEqual(component.streamID, "1080-combined")
    }

    func testAdaptive1080ChosenWhenCombinedMissing() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(resolution: 1080, kind: .videoOnly)],
            audioOnly: [makeStream(resolution: nil, kind: .audioOnly)]
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p1080)
        guard case let .adaptive(video, audio, resolution) = plan else {
            XCTFail("Expected adaptive 1080 plan, got \(plan)")
            return
        }
        XCTAssertEqual(resolution, 1080)
        XCTAssertEqual(video.sourceURL.absoluteString, "https://e/1080")
        XCTAssertEqual(audio.sourceURL.absoluteString, "https://e/audio")
    }

    func testRequested1080NeverFallsBackTo720() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(resolution: 720, kind: .combined)],
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
            combined: [makeStream(resolution: 2160, kind: .combined)],
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
            combined: [makeStream(resolution: 720, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let plan = DownloadPlanner.plan(for: media, quality: .p720)
        guard case let .combined(component, resolution) = plan else {
            XCTFail("Expected combined 720 plan, got \(plan)")
            return
        }
        XCTAssertEqual(resolution, 720)
        XCTAssertEqual(component.sourceURL.absoluteString, "https://e/720")
    }

    func testAdaptive720NotSilentlyDowngradedFrom1080() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [],
            videoOnly: [makeStream(resolution: 720, kind: .videoOnly)],
            audioOnly: [makeStream(resolution: nil, kind: .audioOnly)]
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
