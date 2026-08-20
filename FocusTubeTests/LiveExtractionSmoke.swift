import XCTest
@testable import FocusTube
import FocusTubeCore

/// Opt-in live smoke: runs only when FOCUSTUBE_LIVE_SMOKE=1 is set in the
/// environment. Kept separate from deterministic merge gates so normal CI does
/// not depend on live YouTube availability or network stability. Exercises the
/// real local-only YouTubeKit extraction boundary end to end.
final class LiveExtractionSmoke: XCTestCase {
    func testLocalExtractionProducesAllowedStream() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FOCUSTUBE_LIVE_SMOKE"] != "1",
            "Opt-in live smoke; set FOCUSTUBE_LIVE_SMOKE=1 to run against YouTube."
        )

        let resolved = try await YouTubeKitMediaExtractor().resolve(videoID: "dQw4w9WgXcQ")
        let filtered = MediaStreamFilter.filter(resolved)

        if filtered.combined.isEmpty {
            XCTFail("No allowed combined stream resolved for live sample")
        } else {
            XCTAssertLessThanOrEqual(filtered.combined.map { $0.resolution ?? 0 }.max() ?? 0, 1080)
        }
    }
}
