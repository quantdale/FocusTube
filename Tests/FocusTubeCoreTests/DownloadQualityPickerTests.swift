import XCTest
@testable import FocusTubeCore

final class DownloadQualityPickerTests: XCTestCase {
    func makeStream(resolution: Int, kind: StreamKind) -> MediaStream {
        MediaStream(
            id: "\(resolution)-\(kind)",
            videoID: "v",
            resolution: resolution,
            kind: kind,
            nativePlayable: true,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: URL(string: "https://e/\(resolution)")!,
            expiresAt: nil
        )
    }

    func testPickerShowsOnlyAvailableSubset() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(resolution: 1080, kind: .combined), makeStream(resolution: 720, kind: .combined)],
            videoOnly: [makeStream(resolution: 480, kind: .videoOnly)],
            audioOnly: []
        )
        let picker = DownloadQualityPicker()
        let available = picker.availableQualities(from: media)
        XCTAssertEqual(available.map { $0.rawValue }, [1080, 720, 480])
        XCTAssertFalse(picker.isAvailable(.p360, from: media))
        XCTAssertTrue(picker.isAvailable(.p1080, from: media))
    }

    func testPickerNeverFabricatesMissingQuality() {
        let media = ResolvedMedia(
            videoID: "v",
            extractedAt: Date(),
            combined: [makeStream(resolution: 720, kind: .combined)],
            videoOnly: [],
            audioOnly: []
        )
        let picker = DownloadQualityPicker()
        let available = picker.availableQualities(from: media)
        XCTAssertEqual(available, [.p720])
    }
}
