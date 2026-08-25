import XCTest
import AVFoundation
@testable import FocusTube

/// Red-gate repair (run 32828052990) regression coverage: the DEBUG fixture
/// media factory must produce a genuinely decodable MP4. The aebae44 wave
/// dropped `writer.finishWriting()`, so every generation deterministically
/// expired with FixtureMedia Code=4 while the (since removed) opaque-filler
/// fallback still registered fake completed downloads that only failed later
/// at playback. These tests surface that recurrence in the cheap unit bundle,
/// before any full XCUITest journey.
final class FixtureMediaTests: XCTestCase {
    func testMasterPlayableFileIsGenuinelyDecodable() async throws {
        let url = try FixtureMediaFactory.masterPlayableFile()

        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(videoTracks.isEmpty, "fixture master must contain a decodable video track")

        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0, "fixture master must have a positive duration")
    }

    func testTempCopiesAreDistinctConsumableFilesPerComponent() throws {
        let copyA = try FixtureMediaFactory.tempCopy(for: "req-fixmed", component: 0)
        let copyB = try FixtureMediaFactory.tempCopy(for: "req-fixmed", component: 1)

        XCTAssertNotEqual(copyA, copyB, "every completed event needs its own consumable path")
        for copy in [copyA, copyB] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
            let size = try Data(contentsOf: copy).count
            XCTAssertGreaterThan(size, 4, "fixture copies carry real encoded media, not filler bytes")
        }
    }
}
