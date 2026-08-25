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

    func testDurationParsingSupportsLongFormVariantsAndStaysAnchored() {
        XCTAssertEqual(VideoSummary.duration(from: "PT1H2M3S"), 3723)
        // Day/week forms YouTube uses for >24h content.
        XCTAssertEqual(VideoSummary.duration(from: "P1DT2H30M0S"), 95_400)
        XCTAssertEqual(VideoSummary.duration(from: "P2W"), 1_209_600)
        XCTAssertEqual(VideoSummary.duration(from: "PT90S"), 90)
        // Fractional seconds floor; no fabricated precision.
        XCTAssertEqual(VideoSummary.duration(from: "PT1M30.5S"), 90)
        // Live/upcoming placeholders degrade to unknown duration.
        XCTAssertNil(VideoSummary.duration(from: "P0D"))
        // Anchored: embedded/garbage shapes never partially match.
        XCTAssertNil(VideoSummary.duration(from: "xPT1M"))
        XCTAssertNil(VideoSummary.duration(from: "PT"))
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

    // MARK: - HB-015 403 taxonomy

    func testPermissionDeniedStatusEnvelopeMapsToForbidden() async {
        // New-style envelope: canonical status without legacy errors[] reasons.
        let envelope = Data("""
        {"error":{"code":403,"message":"The caller does not have permission","status":"PERMISSION_DENIED"}}
        """.utf8)
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: envelope, statusCode: 403))
        do {
            _ = try await client.fetchVideoDetails(ids: ["v1"], accessToken: "tok")
            XCTFail("expected .forbidden")
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLegacyPermissionReasonsMapToForbiddenAndQuotaReasonsStayRetryable() async {
        let cases: [(reason: String, status: String?, expected: YouTubeAPIError)] = [
            ("insufficientPermissions", nil, .forbidden),
            ("forbidden", nil, .forbidden),
            ("quotaExceeded", nil, .quotaExceeded),
            ("dailyLimitExceeded", nil, .quotaExceeded),
            ("rateLimitExceeded", nil, .quotaExceeded),
            ("userRateLimitExceeded", nil, .quotaExceeded),
            ("someUnknownFutureReason", nil, .quotaExceeded) // deliberate fallback
        ]
        for entry in cases {
            let body: String
            if let status = entry.status {
                body = "{\"error\":{\"code\":403,\"status\":\"\(status)\",\"errors\":[{\"reason\":\"\(entry.reason)\"}]}}"
            } else {
                body = "{\"error\":{\"code\":403,\"errors\":[{\"reason\":\"\(entry.reason)\"}]}}"
            }
            let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: Data(body.utf8), statusCode: 403))
            do {
                _ = try await client.fetchVideoDetails(ids: ["v1"], accessToken: "tok")
                XCTFail("\(entry.reason): expected error")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, entry.expected, entry.reason)
            } catch {
                XCTFail("\(entry.reason): unexpected error: \(error)")
            }
        }
    }

    func testCanonicalResourceExhaustedStatusMapsToQuotaExceeded() async {
        let envelope = Data("""
        {"error":{"code":403,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED"}}
        """.utf8)
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: envelope, statusCode: 403))
        do {
            _ = try await client.searchVideoIDs(query: "q", accessToken: "tok", pageToken: nil)
            XCTFail("expected .quotaExceeded")
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPermissionDeniedOnCommentFetchDoesNotMasqueradeAsDisabledComments() async {
        // A permission denial must NOT collapse into the commentsDisabled
        // product state — the video's comments may be perfectly visible to
        // users who have access.
        let envelope = Data("""
        {"error":{"code":403,"status":"PERMISSION_DENIED"}}
        """.utf8)
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: envelope, statusCode: 403))
        let service = CommentsService(api: client)
        do {
            _ = try await service.comments(videoID: "v1", accessToken: "tok")
            XCTFail("expected .forbidden")
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - HB-018 pre-wire resource-id validation

    /// A performer that fails the test if any network work is attempted.
    private struct NoNetworkPerformer: HTTPPerforming {
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            XCTFail("no network call may be made for invalid input: \(request.url?.absoluteString ?? "nil")")
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
    }

    func testEmptyResourceIDsAreRejectedWithoutNetworkAcrossEndpoints() async {
        let client = YouTubeDataClient(performer: NoNetworkPerformer())
        let empty = "   "
        await expectInvalidInput { try await client.subscribe(channelID: empty, accessToken: "t") }
        await expectInvalidInput { try await client.unsubscribe(subscriptionID: empty, accessToken: "t") }
        await expectInvalidInput { try await client.rateVideo(videoID: empty, rating: .like, accessToken: "t") }
        await expectInvalidInput { _ = try await client.findMySubscription(channelID: empty, accessToken: "t") }
        await expectInvalidInput { _ = try await client.fetchMyVideoRating(videoID: empty, accessToken: "t") }
        await expectInvalidInput { try await client.addToPlaylist(playlistID: empty, videoID: "v", accessToken: "t") }
        await expectInvalidInput { try await client.addToPlaylist(playlistID: "PL", videoID: empty, accessToken: "t") }
        await expectInvalidInput { try await client.removeFromPlaylist(playlistItemID: empty, accessToken: "t") }
        await expectInvalidInput { _ = try await client.fetchComments(videoID: empty, accessToken: "t", pageToken: nil) }
        await expectInvalidInput { _ = try await client.fetchPlaylistVideoIDs(playlistID: empty, accessToken: "t", pageToken: nil) }
        await expectInvalidInput { _ = try await client.fetchPlaylistItems(playlistID: empty, accessToken: "t") }
        await expectInvalidInput { _ = try await client.postTopLevelComment(videoID: empty, text: "hi", accessToken: "t") }
    }

    private func expectInvalidInput(_ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected .invalidInput")
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .invalidInput)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - HB-016 tolerant item decode

    private static let oneGoodOneBadVideosJSON = """
    {"items":[
      {"id":"good","snippet":{"title":"OK","channelTitle":"C","publishedAt":"2024-01-01T00:00:00Z","description":"d","thumbnails":{}},"contentDetails":{"duration":"PT1M"}},
      {"id":"bad","snippet":{"title":42},"contentDetails":{"duration":"PT1M"}}
    ]}
    """

    func testSingleMalformedItemSkipsWithoutFailingThePageAndReportsCount() async throws {
        final class Recorder: @unchecked Sendable {
            var calls: [(endpoint: String, count: Int)] = []
        }
        let recorder = Recorder()
        let client = YouTubeDataClient(
            performer: FakeHTTPPerformer(data: Data(Self.oneGoodOneBadVideosJSON.utf8), statusCode: 200),
            onItemsSkipped: { endpoint, count in recorder.calls.append((endpoint, count)) }
        )
        let summaries = try await client.fetchVideoDetails(ids: ["good", "bad"], accessToken: "tok")
        XCTAssertEqual(summaries.map { $0.id }, ["good"])
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.endpoint, "youtube.videos")
        XCTAssertEqual(recorder.calls.first?.count, 1)
    }

    func testAllMalformedItemsStillThrowDecodeInsteadOfSilentEmptyPage() async {
        let payload = Data("""
        {"items":[{"snippet":{"title":42}},{"contentDetails":{}}]}
        """.utf8)
        let reported = LockedFlag()
        let client = YouTubeDataClient(
            performer: FakeHTTPPerformer(data: payload, statusCode: 200),
            onItemsSkipped: { _, _ in reported.flag = true }
        )
        do {
            _ = try await client.fetchVideoDetails(ids: ["x"], accessToken: "tok")
            XCTFail("expected .decode when every item is malformed")
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .decode)
            XCTAssertFalse(reported.flag, "all-malformed pages surface as errors, not skips")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - HB-021 cached fractional-capable RFC3339 parsing

    func testPublishedAtSupportsFractionalSecondsAndPlainForms() async throws {
        let json = Data("""
        {"items":[
          {"id":"plain","snippet":{"title":"A","channelTitle":"C","publishedAt":"2024-01-01T00:00:00Z","description":"d","thumbnails":{}},"contentDetails":{"duration":"PT1M"}},
          {"id":"frac","snippet":{"title":"B","channelTitle":"C","publishedAt":"2024-01-01T00:00:00.250Z","description":"d","thumbnails":{}},"contentDetails":{"duration":"PT2M"}}
        ]}
        """.utf8)
        let client = YouTubeDataClient(performer: FakeHTTPPerformer(data: json, statusCode: 200))
        let summaries = try await client.fetchVideoDetails(ids: ["plain", "frac"], accessToken: "tok")
        XCTAssertNotNil(summaries.first { $0.id == "plain" }?.publishedAt)
        XCTAssertNotNil(summaries.first { $0.id == "frac" }?.publishedAt,
                        "fractional-second timestamps must not silently parse to nil")
    }

    // MARK: - HB-030 commentThreads pageToken plumbing

    func testCommentThreadsPaginationTokenPlumbing() async throws {
        let threadsJSON = Data("""
        {"nextPageToken":"ct-next","items":[{"id":"t1","snippet":{"topLevelComment":{"id":"c1","snippet":{"authorDisplayName":"A","textDisplay":"T","publishedAt":"2024-01-01T00:00:00Z"}},"totalReplyCount":0}}]}
        """.utf8)
        let performer = ScriptedPerformer(responses: [(threadsJSON, 200)])
        let client = YouTubeDataClient(performer: performer)

        let page = try await client.fetchComments(videoID: "v1", accessToken: "tok", pageToken: "ct-2")
        XCTAssertEqual(page.comments.map { $0.id }, ["c1"])
        XCTAssertEqual(page.nextPageToken, "ct-next")
        var query = Self.query(of: performer.requests[0])
        XCTAssertEqual(query["videoId"], "v1")
        XCTAssertEqual(query["pageToken"], "ct-2")

        // First page: no pageToken parameter is sent at all.
        _ = try await client.fetchComments(videoID: "v1", accessToken: "tok", pageToken: nil)
        query = Self.query(of: performer.requests[1])
        XCTAssertNil(query["pageToken"])
    }
}

/// Minimal thread-safe flag for skip-reporter assertions.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var flag: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
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
