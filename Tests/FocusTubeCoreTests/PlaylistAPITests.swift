import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FocusTubeCore

/// DDV2-08: bounded supported-playlists API — list mine, read items with
/// removable ids, insert, delete. Request shapes + decoding + error mapping.
final class PlaylistAPITests: XCTestCase {
    private final class CapturingPerformer: HTTPPerforming, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        let data: Data
        let statusCode: Int

        init(data: Data, statusCode: Int = 200) {
            self.data = data
            self.statusCode = statusCode
        }

        var lastRequest: URLRequest? { lock.withLock { requests.last } }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { requests.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    private func queryItems(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testFetchMyPlaylistsDecodesTitlesAndCounts() async throws {
        let body = """
        {"items":[{"id":"PL1","snippet":{"title":"Watch Again"},
        "status":{"privacyStatus":"private"},
        "contentDetails":{"itemCount":12}}]}
        """
        let performer = CapturingPerformer(data: Data(body.utf8))
        let client = YouTubeDataClient(performer: performer)

        let playlists = try await client.fetchMyPlaylists(accessToken: "tok")

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists.first?.id, "PL1")
        XCTAssertEqual(playlists.first?.title, "Watch Again")
        XCTAssertEqual(playlists.first?.itemCount, 12)
        XCTAssertEqual(queryItems(performer.lastRequest)["mine"], "true")
    }

    func testFetchPlaylistItemsCarriesRemovableResourceID() async throws {
        let body = """
        {"items":[{"id":"PI9","snippet":{"title":"Item Title",
        "channelTitle":"Chan","videoOwnerChannelTitle":"Owner",
        "videoOwnerChannelId":"UCowner123","description":"Item description text",
        "thumbnails":{"medium":{"url":"https://t/pi9.jpg"}}},
        "contentDetails":{"videoId":"vid7"}}]}
        """
        let performer = CapturingPerformer(data: Data(body.utf8))
        let client = YouTubeDataClient(performer: performer)

        let items = try await client.fetchPlaylistItems(playlistID: "PL1", accessToken: "tok")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.playlistItemID, "PI9", "removal needs the playlistItem id")
        XCTAssertEqual(items.first?.videoID, "vid7", "playback needs the video id")
        XCTAssertEqual(items.first?.channelTitle, "Owner")
        XCTAssertEqual(items.first?.channelID, "UCowner123", "Subscribe must survive playlist-origin navigation")
        XCTAssertEqual(items.first?.videoDescription, "Item description text")
        XCTAssertEqual(items.first?.thumbnailURL, "https://t/pi9.jpg")
        XCTAssertEqual(queryItems(performer.lastRequest)["playlistId"], "PL1")
    }

    func testAddToPlaylistPostsResourceIDBody() async throws {
        let performer = CapturingPerformer(data: Data())
        let client = YouTubeDataClient(performer: performer)

        try await client.addToPlaylist(playlistID: "PL1", videoID: "vid7", accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url!.path.hasSuffix("/playlistItems"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let snippet = try XCTUnwrap(json["snippet"] as? [String: Any])
        XCTAssertEqual(snippet["playlistId"] as? String, "PL1")
        let resource = try XCTUnwrap(snippet["resourceId"] as? [String: Any])
        XCTAssertEqual(resource["kind"] as? String, "youtube#video")
        XCTAssertEqual(resource["videoId"] as? String, "vid7")
    }

    func testRemoveFromPlaylistIssuesDeleteWithItemID() async throws {
        let performer = CapturingPerformer(data: Data())
        let client = YouTubeDataClient(performer: performer)

        try await client.removeFromPlaylist(playlistItemID: "PI9", accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(queryItems(request)["id"], "PI9")
    }

    func testPlaylistEndpointsMapTypedErrors() async {
        for status in [401, 403] {
            let expected: YouTubeAPIError = status == 401 ? .unauthorized : .quotaExceeded
            let client = YouTubeDataClient(performer: CapturingPerformer(data: Data(), statusCode: status))
            do {
                _ = try await client.fetchMyPlaylists(accessToken: "tok")
                XCTFail("expected \(expected)")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, expected)
            } catch { XCTFail("unexpected: \(error)") }
        }
    }
}
