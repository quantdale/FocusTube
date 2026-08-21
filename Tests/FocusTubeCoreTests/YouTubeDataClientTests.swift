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

    // HB-011a: every endpoint that decodes a success body must surface
    // malformed payloads as the typed `.decode` error, never crash or
    // mis-decode into partial results.
    private enum DecodingEndpoint: String {
        case subscriptions
        case playlistItems
        case videos
        case search
        case commentThreads
    }

    func testMalformedPayloadsMapToDecodeErrorOnEveryDecodingEndpoint() async {
        for entry in Self.malformedPayloadCases {
            let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(entry.payload.utf8), statusCode: 200))
            do {
                _ = try await Self.call(entry.endpoint, on: client)
                XCTFail("\(entry.endpoint.rawValue) [\(entry.category)]: expected .decode, got success")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, .decode, "\(entry.endpoint.rawValue) [\(entry.category)]")
            } catch {
                XCTFail("\(entry.endpoint.rawValue) [\(entry.category)]: unexpected error: \(error)")
            }
        }
    }

    func testMalformedErrorBodyFallsBackToStatusMapping() async {
        // A non-2xx body that fails error-envelope decoding must map by status
        // code alone, never crash or leak decoder internals.
        let bodies: [(category: String, body: String)] = [
            ("truncated", "{\"error\":{\"errors\":[{\"reason\":\"comm"),
            ("wrong-typed", "{\"error\":{\"errors\":\"quota\"}}"),
            ("missing-errors", "{\"error\":{\"message\":\"blocked\"}}"),
            ("envelope-array", "[]")
        ]
        for entry in bodies {
            let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(entry.body.utf8), statusCode: 403))
            do {
                _ = try await client.fetchVideoDetails(ids: ["v1"], accessToken: "tok")
                XCTFail("\(entry.category): expected .quotaExceeded, got success")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, .quotaExceeded, entry.category)
            } catch {
                XCTFail("\(entry.category): unexpected error: \(error)")
            }
        }
    }

    // HB-011a: the documented detection condition — HTTP 403 whose error
    // envelope carries reason "commentsDisabled" — must surface as the typed
    // outcome through CommentsService, not as a generic quota failure.
    func testCommentsDisabled403EnvelopeSurfacesTypedErrorThroughCommentsService() async {
        let envelope = """
        {"error":{"code":403,"message":"The video identified by the videoId parameter has disabled comments.","errors":[{"message":"The video identified by the videoId parameter has disabled comments.","domain":"youtube.commentThread","reason":"commentsDisabled","location":"videoId","locationType":"parameter"}]}}
        """.data(using: .utf8)!
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: envelope, statusCode: 403))
        let service = CommentsService(api: client)
        do {
            _ = try await service.comments(videoID: "v1", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .commentsDisabled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testQuota403EnvelopeWithoutCommentsDisabledReasonStaysGeneric() async {
        let envelope = """
        {"error":{"code":403,"message":"Quota exceeded.","errors":[{"message":"quota","domain":"youtube.global","reason":"quotaExceeded","location":"","locationType":""}]}}
        """.data(using: .utf8)!
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: envelope, statusCode: 403))
        let service = CommentsService(api: client)
        do {
            _ = try await service.comments(videoID: "v1", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .quotaExceeded)
            XCTAssertNotEqual(error, .commentsDisabled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
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

    private static let malformedPayloadCases: [(endpoint: DecodingEndpoint, category: String, payload: String)] = [
        (.subscriptions, "truncated", """
        {"items":[{"contentDetails":{"relatedPlaylists":{"uploads":"PL1"
        """),
        (.subscriptions, "wrong-typed-field", """
        {"items":[{"contentDetails":{"relatedPlaylists":{"uploads":123}}}]}
        """),
        (.subscriptions, "missing-required-field", """
        {"items":[{"contentDetails":{"relatedPlaylists":{}}}]}
        """),
        (.subscriptions, "unexpected-envelope", "[]"),
        (.playlistItems, "truncated", """
        {"items":[{"contentDetails":{"videoId":"v1"
        """),
        (.playlistItems, "wrong-typed-field", """
        {"items":[{"contentDetails":{"videoId":42}}]}
        """),
        (.playlistItems, "missing-required-field", """
        {"items":[{"contentDetails":{}}]}
        """),
        (.playlistItems, "unexpected-envelope", """
        {"items":null}
        """),
        (.videos, "truncated", """
        {"items":[{"id":"v1","snippet":{"title":"T"
        """),
        (.videos, "wrong-typed-field", """
        {"items":[{"id":"v1","snippet":{"title":"T","channelTitle":"C","publishedAt":"2024-01-01T00:00:00Z","description":"d","thumbnails":{"medium":{"url":"https://t/x.jpg"}}},"contentDetails":{"duration":3723}}]}
        """),
        (.videos, "missing-required-field", """
        {"items":[{"id":"v1","contentDetails":{"duration":"PT1M"}}]}
        """),
        (.videos, "unexpected-envelope", "null"),
        (.search, "truncated", """
        {"items":[{"id":{"videoId":"v1"
        """),
        (.search, "wrong-typed-field", """
        {"items":[{"id":"not-an-object"}]}
        """),
        (.search, "missing-required-field", """
        {"items":[{"videoId":"v1"}]}
        """),
        (.search, "unexpected-envelope", """
        {"unexpected":true}
        """),
        (.commentThreads, "truncated", """
        {"items":[{"id":"t1","snippet":{"topLevelComment":{"id":"c1"
        """),
        (.commentThreads, "wrong-typed-field", """
        {"items":[{"id":"t1","snippet":{"topLevelComment":{"id":"c1","snippet":{"authorDisplayName":5,"textDisplay":"T","publishedAt":"2024-01-01T00:00:00Z"}},"totalReplyCount":0}}]}
        """),
        (.commentThreads, "missing-required-field", """
        {"items":[{"id":"t1","snippet":{"topLevelComment":{"id":"c1","snippet":{"authorDisplayName":"A","publishedAt":"2024-01-01T00:00:00Z"}}}}]}
        """),
        (.commentThreads, "unexpected-envelope", """
        {"error":{"message":"nope"}}
        """)
    ]

    private static func call(_ endpoint: DecodingEndpoint, on client: YouTubeDataClient) async throws {
        switch endpoint {
        case .subscriptions: _ = try await client.fetchSubscriptionUploadsPlaylistIDs(accessToken: "tok")
        case .playlistItems: _ = try await client.fetchPlaylistVideoIDs(playlistID: "PL1", accessToken: "tok", pageToken: nil)
        case .videos: _ = try await client.fetchVideoDetails(ids: ["v1"], accessToken: "tok")
        case .search: _ = try await client.searchVideoIDs(query: "q", accessToken: "tok", pageToken: nil)
        case .commentThreads: _ = try await client.fetchComments(videoID: "v1", accessToken: "tok", pageToken: nil)
        }
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
