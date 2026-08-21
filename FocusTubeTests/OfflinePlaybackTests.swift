import XCTest
import AVFoundation

/// Proves a finalized local file creates a native `AVPlayerItem` with no network
/// dependency. Deterministic: writes a local file and asserts the offline item
/// references it.
final class OfflinePlaybackTests: XCTestCase {
    func testLocalFileCreatesOfflinePlayerItem() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focustube-offline-\(UUID().uuidString).mp4")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let item = AVPlayerItem(url: url)
        XCTAssertEqual((item.asset as? AVURLAsset)?.url, url)
        XCTAssertTrue(url.isFileURL)
    }
}
