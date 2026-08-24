import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FocusTubeCore

/// DDV2-03: typed comment mutation + account-state lookup endpoints.
/// Request construction, payload shapes, decoding, and error mapping are all
/// verified against a recording performer — never live credentials.
final class CommentMutationAPITests: XCTestCase {
    private final class CapturingPerformer: HTTPPerforming, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        let data: Data
        let statusCode: Int
        let throwsError: Bool

        init(data: Data, statusCode: Int = 200, throwsError: Bool = false) {
            self.data = data
            self.statusCode = statusCode
            self.throwsError = throwsError
        }

        var lastRequest: URLRequest? { lock.withLock { requests.last } }
        var callCount: Int { lock.withLock { requests.count } }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { requests.append(request) }
            if throwsError {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    private func queryItems(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func jsonBody(_ request: URLRequest?) throws -> [String: Any] {
        let body = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Top-level comment

    func testPostTopLevelCommentBuildsInsertRequestAndDecodesStoredComment() async throws {
        let body = """
        {"id":"t1","snippet":{"videoId":"vid","topLevelComment":{"id":"c-new",
        "snippet":{"authorDisplayName":"Me","textDisplay":"Hello","likeCount":0,
        "publishedAt":"2026-08-24T00:00:00Z"}}}}
        """
        let performer = CapturingPerformer(data: Data(body.utf8))
        let client = YouTubeDataClient(performer: performer)

        let comment = try await client.postTopLevelComment(videoID: "vid", text: "Hello", accessToken: "tok")

        XCTAssertEqual(comment.id, "c-new")
        XCTAssertEqual(comment.author, "Me")
        XCTAssertEqual(comment.text, "Hello")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/commentThreads"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(queryItems(request)["part"], "snippet")
        let json = try jsonBody(request)
        let snippet = try XCTUnwrap(json["snippet"] as? [String: Any])
        XCTAssertEqual(snippet["videoId"] as? String, "vid")
        let topLevel = try XCTUnwrap(snippet["topLevelComment"] as? [String: Any])
        let inner = try XCTUnwrap(topLevel["snippet"] as? [String: Any])
        XCTAssertEqual(inner["textOriginal"] as? String, "Hello")
    }

    func testPostReplyBuildsCommentsInsertRequestWithParentID() async throws {
        let body = """
        {"id":"r-new","snippet":{"parentId":"c1","authorDisplayName":"Me",
        "textDisplay":"Reply text","likeCount":0,"publishedAt":"2026-08-24T00:00:00Z"}}
        """
        let performer = CapturingPerformer(data: Data(body.utf8))
        let client = YouTubeDataClient(performer: performer)

        let reply = try await client.postReply(parentCommentID: "c1", text: "  Reply text  ", accessToken: "tok")

        XCTAssertEqual(reply.id, "r-new")
        XCTAssertEqual(reply.text, "Reply text", "trimmed input must be what is submitted and returned")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/comments"))
        XCTAssertEqual(request.httpMethod, "POST")
        let json = try jsonBody(request)
        let snippet = try XCTUnwrap(json["snippet"] as? [String: Any])
        XCTAssertEqual(snippet["parentId"] as? String, "c1")
        XCTAssertEqual(snippet["textOriginal"] as? String, "Reply text")
    }

    func testPostEndpointsMapTypedErrors() async {
        let cases: [(status: Int, expected: YouTubeAPIError)] = [
            (401, .unauthorized), (403, .quotaExceeded), (404, .notFound)
        ]
        for entry in cases {
            let client = YouTubeDataClient(performer: CapturingPerformer(data: Data(), statusCode: entry.status))
            do {
                _ = try await client.postTopLevelComment(videoID: "v", text: "x", accessToken: "tok")
                XCTFail("expected \(entry.expected)")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, entry.expected)
            } catch { XCTFail("unexpected: \(error)") }

            do {
                _ = try await client.postReply(parentCommentID: "c", text: "x", accessToken: "tok")
                XCTFail("expected \(entry.expected)")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, entry.expected)
            } catch { XCTFail("unexpected: \(error)") }
        }
    }

    func testPostEndpointNetworkFailureMapped() async {
        let client = YouTubeDataClient(performer: CapturingPerformer(data: Data(), throwsError: true))
        do {
            _ = try await client.postReply(parentCommentID: "c", text: "x", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .network)
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testPostEndpointMalformedPayloadMapsToDecode() async {
        let client = YouTubeDataClient(performer: CapturingPerformer(data: "not json".data(using: .utf8)!))
        do {
            _ = try await client.postTopLevelComment(videoID: "v", text: "x", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .decode)
        } catch { XCTFail("unexpected: \(error)") }
    }

    // MARK: - Validation before network

    func testInvalidTextIsRejectedWithoutAnyNetworkCall() async throws {
        let performer = CapturingPerformer(data: Data())
        let client = YouTubeDataClient(performer: performer)

        for bad in ["", "   ", "\n\t", String(repeating: "x", count: 10_001)] {
            do {
                _ = try await client.postTopLevelComment(videoID: "v", text: bad, accessToken: "tok")
                XCTFail("expected invalidInput")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, .invalidInput)
            } catch { XCTFail("unexpected: \(error)") }

            do {
                _ = try await client.postReply(parentCommentID: "c", text: bad, accessToken: "tok")
                XCTFail("expected invalidInput")
            } catch let error as YouTubeAPIError {
                XCTAssertEqual(error, .invalidInput)
            } catch { XCTFail("unexpected: \(error)") }
        }
        XCTAssertEqual(performer.callCount, 0, "validation must reject before any network work")
        // Boundary: exactly the documented limit is accepted.
        XCTAssertNotNil(YouTubeDataClient.validatedCommentText(String(repeating: "x", count: 10_000)))
    }

    func testEmptyParentIDRejectedWithoutNetwork() async throws {
        let performer = CapturingPerformer(data: Data())
        let client = YouTubeDataClient(performer: performer)
        do {
            _ = try await client.postReply(parentCommentID: "", text: "x", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .invalidInput)
        } catch { XCTFail("unexpected: \(error)") }
        XCTAssertEqual(performer.callCount, 0)
    }

    // MARK: - Subscription lookup

    func testFindMySubscriptionFiltersMineAndForChannelAndDecodesResourceID() async throws {
        let found = """
        {"items":[{"id":"SUB123","snippet":{"title":"Channel Title"}}]}
        """
        let performer = CapturingPerformer(data: Data(found.utf8))
        let client = YouTubeDataClient(performer: performer)

        let lookup = try await client.findMySubscription(channelID: "UC1", accessToken: "tok")

        XCTAssertEqual(lookup?.subscriptionID, "SUB123")
        XCTAssertEqual(lookup?.channelTitle, "Channel Title")
        let query = queryItems(performer.lastRequest)
        XCTAssertEqual(query["mine"], "true")
        XCTAssertEqual(query["forChannelId"], "UC1")
    }

    func testFindMySubscriptionReturnsNilWhenNotSubscribed() async throws {
        let client = YouTubeDataClient(performer: CapturingPerformer(data: Data(#"{"items":[]}"#.utf8)))
        let none = try await client.findMySubscription(channelID: "UC1", accessToken: "tok")
        XCTAssertNil(none, "absent subscription must be a normal nil result, not an error")
    }

    // MARK: - Rating state

    func testFetchMyVideoRatingDecodesAllStatesIncludingFallbacks() async throws {
        for (raw, expected) in [("like", VideoRatingState.like), ("dislike", .dislike), ("none", .none), ("unspecified", .unspecified), ("weird", .unspecified)] {
            let body = #"{"items":[{"videoId":"v","rating":"\#(raw)"}]}"#
            let client = YouTubeDataClient(performer: CapturingPerformer(data: Data(body.utf8)))
            let state = try await client.fetchMyVideoRating(videoID: "v", accessToken: "tok")
            XCTAssertEqual(state, expected, raw)
        }
        // Empty items → unspecified rather than a decode failure.
        let empty = YouTubeDataClient(performer: CapturingPerformer(data: Data(#"{"items":[]}"#.utf8)))
        let emptyState = try await empty.fetchMyVideoRating(videoID: "v", accessToken: "tok")
        XCTAssertEqual(emptyState, .unspecified)
    }
}
