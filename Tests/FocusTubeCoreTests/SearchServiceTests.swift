import XCTest
@testable import FocusTubeCore

private struct SearchStubAPI: YouTubeAPI {
    var searchIDs: [String]
    var nextPageToken: String?
    var details: [VideoSummary]

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String] { [] }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { details }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        return (searchIDs, nextPageToken)
    }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { .disabled }
    func subscribe(channelID: String, accessToken: String) async throws {}
    func unsubscribe(subscriptionID: String, accessToken: String) async throws {}
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}
    func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary] { [] }
}

final class SearchServiceTests: XCTestCase {
    func summary(id: String, duration: Int?) -> VideoSummary {
        VideoSummary(id: id, title: id, channelTitle: "C", durationSeconds: duration, publishedAt: nil, thumbnailURL: nil, description: nil)
    }

    func testEmptyQueryReturnsNothingWithoutAPICall() async throws {
        let api = SearchStubAPI(searchIDs: ["x"], nextPageToken: nil, details: [summary(id: "x", duration: 100)])
        let service = SearchService(api: api)
        let page = try await service.search(query: "   ", accessToken: "tok")
        XCTAssertTrue(page.videos.isEmpty)
    }

    func testSearchHydratesAndFiltersShortForm() async throws {
        let api = SearchStubAPI(
            searchIDs: ["long", "short"],
            nextPageToken: "tok2",
            details: [summary(id: "long", duration: 600), summary(id: "short", duration: 30)]
        )
        let service = SearchService(api: api)
        let page = try await service.search(query: "swift", accessToken: "tok")
        XCTAssertEqual(page.videos.map { $0.id }, ["long"])
        XCTAssertEqual(page.nextPageToken, "tok2")
        XCTAssertEqual(page.query, "swift")
    }

    func testQuotaErrorPropagates() async {
        struct FailingAPI: YouTubeAPI {
            func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
            func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String] { [] }
            func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
            func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
                throw YouTubeAPIError.quotaExceeded
            }
            func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { .disabled }
            func subscribe(channelID: String, accessToken: String) async throws {}
            func unsubscribe(subscriptionID: String, accessToken: String) async throws {}
            func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}
            func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary] { [] }
        }
        let service = SearchService(api: FailingAPI())
        do {
            _ = try await service.search(query: "x", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
