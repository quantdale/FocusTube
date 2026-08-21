import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FocusTubeCore

private struct FakeHTTPPerformer: HTTPPerforming {
    var data: Data
    var statusCode: Int
    var throwsError = false

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if throwsError { throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class YouTubeDataClientTests: XCTestCase {
    let validVideosJSON = """
    {"items":[{"id":"vid1","snippet":{"title":"Sample","channelTitle":"Chan",
    "publishedAt":"2024-01-01T00:00:00Z","description":"desc",
    "thumbnails":{"medium":{"url":"https://t/x.jpg"}}},
    "contentDetails":{"duration":"PT1H2M3S"}}]}
    """.data(using: .utf8)!

    func testFetchVideoDetailsDecodes() async throws {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: validVideosJSON, statusCode: 200))
        let summaries = try await client.fetchVideoDetails(ids: ["vid1"], accessToken: "tok")
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.title, "Sample")
        XCTAssertEqual(summaries.first?.durationSeconds, 3723)
        XCTAssertEqual(summaries.first?.thumbnailURL?.absoluteString, "https://t/x.jpg")
    }

    func testUnauthorizedMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(), statusCode: 401))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError { XCTAssertEqual(error, .unauthorized) }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testQuotaExceededMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(), statusCode: 403))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError { XCTAssertEqual(error, .quotaExceeded) }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testNotFoundMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(), statusCode: 404))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError { XCTAssertEqual(error, .notFound) }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testUnknownStatusMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(), statusCode: 500))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError {
            if case .unknown(let status) = error { XCTAssertEqual(status, 500) } else { XCTFail() }
        }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testDecodeFailureMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: "not json".data(using: .utf8)!, statusCode: 200))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError { XCTAssertEqual(error, .decode) }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testNetworkFailureMapped() async {
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(), statusCode: 200, throwsError: true))
        do { _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok"); XCTFail() }
        catch let error as YouTubeAPIError { XCTAssertEqual(error, .network) }
        catch { XCTFail("unexpected error: \(error)") }
    }

    func testSubscriptionFeedAggregates() async throws {
        let subsJSON = """
        {"items":[{"contentDetails":{"relatedPlaylists":{"uploads":"PL1"}}}]}
        """.data(using: .utf8)!
        let playlistJSON = """
        {"items":[{"contentDetails":{"videoId":"vA"}},{"contentDetails":{"videoId":"vB"}}]}
        """.data(using: .utf8)!
        let videosJSON = """
        {"items":[
          {"id":"vA","snippet":{"title":"A","channelTitle":"C","publishedAt":"2024-01-01T00:00:00Z","description":"d","thumbnails":{"medium":{"url":"https://t/a.jpg"}}},"contentDetails":{"duration":"PT10M"}},
          {"id":"vB","snippet":{"title":"B","channelTitle":"C","publishedAt":"2024-01-01T00:00:00Z","description":"d","thumbnails":{"medium":{"url":"https://t/b.jpg"}}},"contentDetails":{"duration":"PT5M"}}
        ]}
        """.data(using: .utf8)!

        let performer = ScriptedPerformer(responses: [
            (subsJSON, 200),
            (playlistJSON, 200),
            (videosJSON, 200)
        ])
        let client = YouTubeDataClient(performer: performer)
        let feed = try await client.fetchSubscriptionFeed(accessToken: "tok")
        XCTAssertEqual(feed.videos.map { $0.id }, ["vA", "vB"])
        XCTAssertNil(feed.nextPageToken)
    }

    func testPlaylistItemsPaginationTokenPlumbing() async throws {
        let playlistJSON = """
        {"nextPageToken":"pt-next","items":[{"contentDetails":{"videoId":"v1"}}]}
        """.data(using: .utf8)!
        let performer = ScriptedPerformer(responses: [(playlistJSON, 200)])
        let client = YouTubeDataClient(performer: performer)

        let page = try await client.fetchPlaylistVideoIDs(playlistID: "PL1", accessToken: "tok", pageToken: "pt-2")
        XCTAssertEqual(page.ids, ["v1"])
        XCTAssertEqual(page.nextPageToken, "pt-next")
        var query = Self.query(of: performer.requests[0])
        XCTAssertEqual(query["playlistId"], "PL1")
        XCTAssertEqual(query["pageToken"], "pt-2")

        // First page: no pageToken parameter is sent at all.
        _ = try await client.fetchPlaylistVideoIDs(playlistID: "PL1", accessToken: "tok", pageToken: nil)
        query = Self.query(of: performer.requests[1])
        XCTAssertNil(query["pageToken"])
    }

    func testSubscriptionFeedChunksVideosListBeyondIDCap() async throws {
        let ids = (0..<61).map { "v\($0)" }
        let subsJSON = Data("{\"items\":[{\"contentDetails\":{\"relatedPlaylists\":{\"uploads\":\"PL1\"}}}]}".utf8)
        let playlistItems = ids.map { "{\"contentDetails\":{\"videoId\":\"\($0)\"}}" }.joined(separator: ",")
        let playlistJSON = Data("{\"items\":[\(playlistItems)]}".utf8)
        let videoItems = ids.map { id in
            "{\"id\":\"\(id)\",\"snippet\":{\"title\":\"\(id)\",\"channelTitle\":\"C\",\"publishedAt\":\"2024-01-01T00:00:00Z\",\"description\":\"d\",\"thumbnails\":{}},\"contentDetails\":{\"duration\":\"PT1M\"}}"
        }.joined(separator: ",")
        let videosJSON = Data("{\"items\":[\(videoItems)]}".utf8)

        // subscriptions -> playlistItems -> two chunked videos.list calls.
        let performer = ScriptedPerformer(responses: [
            (subsJSON, 200),
            (playlistJSON, 200),
            (videosJSON, 200),
            (videosJSON, 200)
        ])
        let client = YouTubeDataClient(performer: performer)
        let feed = try await client.fetchSubscriptionFeed(accessToken: "tok")

        XCTAssertEqual(performer.requests.count, 4)
        let idLists = performer.requests.compactMap { request -> [String]? in
            guard let id = Self.query(of: request)["id"] else { return nil }
            return id.components(separatedBy: ",")
        }
        XCTAssertEqual(idLists.count, 2, "61 ids must split into multiple videos.list calls")
        XCTAssertEqual(idLists[0].count, 50)
        XCTAssertEqual(idLists[1].count, 11)
        XCTAssertEqual(idLists.flatMap { $0 }, ids)
        XCTAssertEqual(feed.videos.count, 122) // each scripted response decodes all 61 items
    }

    private static func query(of request: URLRequest) -> [String: String] {
        guard let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}

// Class (not struct) so `index` can advance across sequential scripted requests;
// @unchecked Sendable is safe here because requests are awaited sequentially.
private final class ScriptedPerformer: HTTPPerforming, @unchecked Sendable {
    var responses: [(Data, Int)]
    private(set) var requests: [URLRequest] = []
    private var index = 0

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let (data, status) = responses[min(index, responses.count - 1)]
        index += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
