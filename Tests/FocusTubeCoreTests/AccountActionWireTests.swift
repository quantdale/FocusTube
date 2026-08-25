import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FocusTubeCore

/// Wire-shape pins for the account-action endpoints that previously had NO
/// request-construction coverage (run-32828052990 audit Finding 1): a malformed
/// body or lost httpMethod here would ship silently and fail for every
/// signed-in user as an opaque runtime error. Verified against a recording
/// performer — never live credentials.
final class AccountActionWireTests: XCTestCase {
    private final class CapturingPerformer: HTTPPerforming, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock { requests.append(request) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        var lastRequest: URLRequest? { lock.withLock { requests.last } }
    }

    private func queryItems(_ request: URLRequest?) -> [String: String] {
        guard let url = request?.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testSubscribePostsChannelResourceBody() async throws {
        let performer = CapturingPerformer()
        let client = YouTubeDataClient(performer: performer)

        try await client.subscribe(channelID: "UCchan", accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/subscriptions"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(queryItems(request)["part"], "snippet")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let snippet = try XCTUnwrap(json["snippet"] as? [String: Any])
        let resource = try XCTUnwrap(snippet["resourceId"] as? [String: Any])
        XCTAssertEqual(resource["kind"] as? String, "youtube#channel")
        XCTAssertEqual(resource["channelId"] as? String, "UCchan")
    }

    func testUnsubscribeDeletesByIDWithoutBody() async throws {
        let performer = CapturingPerformer()
        let client = YouTubeDataClient(performer: performer)

        try await client.unsubscribe(subscriptionID: "SUB-1", accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/subscriptions"))
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(queryItems(request)["id"], "SUB-1")
        XCTAssertNil(request.httpBody, "unsubscribe carries the id as a query parameter only")
    }

    func testRateVideoPostsIDAndRatingQuery() async throws {
        let performer = CapturingPerformer()
        let client = YouTubeDataClient(performer: performer)

        try await client.rateVideo(videoID: "vid9", rating: .like, accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/videos/rate"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(queryItems(request)["id"], "vid9")
        XCTAssertEqual(queryItems(request)["rating"], "like")
    }

    func testRemoveRatingSendsNoneRating() async throws {
        let performer = CapturingPerformer()
        let client = YouTubeDataClient(performer: performer)

        try await client.rateVideo(videoID: "vid9", rating: .none, accessToken: "tok")

        let request = try XCTUnwrap(performer.lastRequest)
        XCTAssertTrue(request.url!.path.hasSuffix("/videos/rate"))
        XCTAssertEqual(queryItems(request)["rating"], "none")
    }
}
