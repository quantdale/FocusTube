import XCTest
@testable import FocusTubeCore

final class YouTubeLinkTests: XCTestCase {
    let vid = YouTubeVideoID("dQw4w9WgXcQ")!
    let pl = YouTubePlaylistID("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")!
    let ch = YouTubeChannelID("UC_x5XG1OV2P6uZZ5FSM9Ttw")!

    func ok(_ s: String) -> YouTubeLink? { try? YouTubeLink.parse(s) }
    func rej(_ s: String) -> YouTubeLink.Rejection? {
        do { _ = try YouTubeLink.parse(s); return nil } catch { return error }
    }

    func testVideoForms() {
        for s in ["https://www.youtube.com/watch?v=dQw4w9WgXcQ", "youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
                  "https://youtu.be/dQw4w9WgXcQ", "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
                  "https://music.youtube.com/watch?v=dQw4w9WgXcQ", "https://www.youtube.com/embed/dQw4w9WgXcQ",
                  "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "https://www.youtube.com/live/dQw4w9WgXcQ",
                  "  https://youtu.be/dQw4w9WgXcQ?si=abc \n"] {
            XCTAssertEqual(ok(s), .video(vid, playlist: nil, startSeconds: nil), s)
        }
    }

    func testVideoWithPlaylistAndTime() {
        XCTAssertEqual(ok("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf&t=1m30s"),
                       .video(vid, playlist: pl, startSeconds: 90))
        XCTAssertEqual(ok("https://youtu.be/dQw4w9WgXcQ?t=42"), .video(vid, playlist: nil, startSeconds: 42))
        XCTAssertEqual(YouTubeLink.parseTime("1h2m3s"), 3723)
        XCTAssertNil(YouTubeLink.parseTime("1x"))
        XCTAssertNil(YouTubeLink.parseTime("1m30"))
    }

    func testPlaylistAndChannel() {
        XCTAssertEqual(ok("https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"), .playlist(pl))
        XCTAssertEqual(ok("https://www.youtube.com/watch?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"), .playlist(pl))
        XCTAssertEqual(ok("https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw"), .channel(ch))
        XCTAssertEqual(ok("https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw/videos"), .channel(ch))
        XCTAssertEqual(ok("UC_x5XG1OV2P6uZZ5FSM9Ttw"), .channel(ch))
        XCTAssertEqual(ch.uploadsPlaylistID, "UU_x5XG1OV2P6uZZ5FSM9Ttw")
    }

    func testRejections() {
        XCTAssertEqual(rej(""), .empty)
        XCTAssertEqual(rej("https://www.youtube.com/shorts/dQw4w9WgXcQ"), .shorts)
        XCTAssertEqual(rej("https://youtube.com/shorts/abc"), .shorts)
        XCTAssertEqual(rej("https://www.youtube.com/@GoogleDevelopers"), .unresolvableChannel("@GoogleDevelopers"))
        XCTAssertEqual(rej("https://www.youtube.com/c/GoogleDevelopers"), .unresolvableChannel("GoogleDevelopers"))
        XCTAssertEqual(rej("https://www.youtube.com/user/GoogleDevelopers"), .unresolvableChannel("GoogleDevelopers"))
        XCTAssertEqual(rej("https://evil.example/watch?v=dQw4w9WgXcQ"), .notYouTube)
        XCTAssertEqual(rej("https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ"), .notYouTube)
        XCTAssertEqual(rej("http://www.youtube.com/watch?v=dQw4w9WgXcQ"), .insecureScheme)
        XCTAssertEqual(rej("https://www.youtube.com/watch?v=bad'id"), .unsupported)
        XCTAssertEqual(rej("https://www.youtube.com/feed/trending"), .unsupported)
        XCTAssertEqual(rej("https://www.youtube.com/channel/notachannel"), .unsupported)
        XCTAssertFalse(YouTubeLink.Rejection.unresolvableChannel("x").userMessage.isEmpty)
    }
}
