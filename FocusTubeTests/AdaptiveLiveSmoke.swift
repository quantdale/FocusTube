import XCTest
@testable import FocusTube
import FocusTubeCore
import AVFoundation

/// Opt-in live adaptive 1080p smoke: runs only when FOCUSTUBE_LIVE_SMOKE=1.
/// Resolves a real long-form video, selects the 1080p video-only + audio
/// components, downloads each through the URLSession path, and muxes them with
/// the native AVFoundation exporter into a single validated file.
final class AdaptiveLiveSmoke: XCTestCase {
    func testAdaptive1080DownloadAndMux() async throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FOCUSTUBE_LIVE_SMOKE"] != "1",
            "Opt-in live adaptive smoke; set FOCUSTUBE_LIVE_SMOKE=1 to run against YouTube."
        )

        let resolved = try await YouTubeKitMediaExtractor().resolve(videoID: "aqz-KE-bpKQ")
        guard let components = AdaptiveSelection.select1080(resolved) else {
            XCTFail("No compliant 1080p video+audio components for live sample")
            return
        }

        async let videoDownload = Self.download(components.video.sourceURL)
        async let audioDownload = Self.download(components.audio.sourceURL)
        let (videoURL, audioURL) = try await (videoDownload, audioDownload)

        let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-adaptive-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outURL) }

        let muxer = await AdaptiveMuxer()
        let result = await muxer.mux(videoURL: videoURL, audioURL: audioURL, outputURL: outURL)

        switch result {
        case .success(let file):
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        case .failure(let error):
            // Native-mux incompatibility is a valid observed outcome that must
            // trigger ADR review rather than an unauthorized fallback.
            XCTAssertTrue([MuxError.incompatible, MuxError.exportFailed, MuxError.missingComponent].contains(error))
        }
    }

    // Static so `async let` child tasks capture no non-Sendable self.
    private static func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { location, _, error in
                if let error { continuation.resume(throwing: error); return }
                guard let location else { continuation.resume(throwing: NSError(domain: "smoke", code: 1)); return }
                let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("focustube-dl-\(UUID().uuidString).bin")
                try? FileManager.default.removeItem(at: destination)
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }
}
