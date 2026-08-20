import XCTest
import AVFoundation

/// Deterministic: native mux must fail with a typed error when given files that
/// contain no compliant video/audio tracks (no FFmpeg/remote fallback).
final class AdaptiveMuxerTests: XCTestCase {
    func testMuxFailsOnNonMediaInput() async {
        let videoURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focustube-mux-v-\(UUID().uuidString).txt")
        let audioURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focustube-mux-a-\(UUID().uuidString).txt")
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focustube-mux-out-\(UUID().uuidString).mp4")
        try! Data("not media".utf8).write(to: videoURL)
        try! Data("not media".utf8).write(to: audioURL)
        defer {
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        let muxer = await AdaptiveMuxer()
        let result = await muxer.mux(videoURL: videoURL, audioURL: audioURL, outputURL: outURL)
        switch result {
        case .success:
            XCTFail("Expected native mux to fail on non-media input")
        case .failure(let error):
            XCTAssertTrue([MuxError.missingComponent, MuxError.incompatible, MuxError.exportFailed].contains(error))
        }
    }
}
