import XCTest
import YouTubeKit
import FocusTubeCore

/// Opt-in live smoke: runs only when FOCUSTUBE_LIVE_SMOKE=1 is set in the
/// environment. Kept separate from deterministic merge gates so normal CI does
/// not depend on live YouTube availability or network stability.
final class LiveExtractionSmoke: XCTestCase {
    func testLocalExtractionProducesAllowedStream() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FOCUSTUBE_LIVE_SMOKE"] != "1",
            "Opt-in live smoke; set FOCUSTUBE_LIVE_SMOKE=1 to run against YouTube."
        )

        let videoID = "dQw4w9WgXcQ"
        let youtube = YouTube(videoID: videoID, methods: [.local])
        let streams = try await youtube.streams

        let combined = streams.filter { $0.includesVideoAndAudioTrack }.map { stream in
            MediaStream(
                id: "\(stream.itag.itag)",
                videoID: videoID,
                resolution: stream.videoResolution,
                kind: .combined,
                nativePlayable: stream.isNativelyPlayable,
                container: stream.fileExtension.rawValue,
                videoCodec: stream.videoCodec?.rawValue,
                audioCodec: stream.audioCodec?.rawValue,
                sourceURL: stream.url,
                expiresAt: nil
            )
        }

        let resolved = ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: combined,
            videoOnly: [],
            audioOnly: []
        )
        let filtered = MediaStreamFilter.filter(resolved)

        if filtered.combined.isEmpty {
            XCTFail("No allowed combined stream resolved for live sample")
        } else {
            XCTAssertLessThanOrEqual(filtered.combined.map { $0.resolution ?? 0 }.max() ?? 0, 1080)
        }
    }
}
