import XCTest
@testable import FocusTubeCore

private struct StubYouTubeAPI: YouTubeAPI {
    var summaries: [VideoSummary]

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String] { [] }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> ([String], String?) { ([], nil) }

    func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary] {
        summaries
    }
}

final class HomeFeedAggregatorTests: XCTestCase {
    func summary(id: String, duration: Int?) -> VideoSummary {
        VideoSummary(id: id, title: id, channelTitle: "C", durationSeconds: duration, publishedAt: nil, thumbnailURL: nil, description: nil)
    }

    func testShortFormRemovedBeforeRender() async throws {
        let api = StubYouTubeAPI(summaries: [
            summary(id: "long", duration: 600),
            summary(id: "short", duration: 60),
            summary(id: "boundary", duration: 180),
            summary(id: "unknown", duration: nil)
        ])
        let aggregator = HomeFeedAggregator(api: api)
        let feed = try await aggregator.fetchFeed(accessToken: "tok")
        XCTAssertEqual(feed.map { $0.id }, ["long", "unknown"])
    }

    func testFilterShortFormPure() {
        let aggregator = HomeFeedAggregator(api: StubYouTubeAPI(summaries: []))
        let items = [
            summary(id: "a", duration: 181),
            summary(id: "b", duration: 179),
            summary(id: "c", duration: 180),
            summary(id: "d", duration: nil)
        ]
        let filtered = aggregator.filterShortForm(items)
        XCTAssertEqual(filtered.map { $0.id }, ["a", "d"])
    }
}
