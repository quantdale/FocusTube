import Foundation
import XCTest
@testable import FocusTubeCore

private struct StubYouTubeAPI: YouTubeReading {
    var feedPage: SubscriptionFeedPage

    init(summaries: [VideoSummary], nextPageToken: String? = nil) {
        self.feedPage = SubscriptionFeedPage(videos: summaries, nextPageToken: nextPageToken)
    }

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { .disabled }
    func subscribe(channelID: String, accessToken: String) async throws {}
    func unsubscribe(subscriptionID: String, accessToken: String) async throws {}
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}

    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        feedPage
    }
}

// Actor so page-token pass-through can be recorded across await boundaries.
    private actor PageRecordingAPI: YouTubeReading {
    let page: SubscriptionFeedPage
    private(set) var receivedTokens: [String?] = []

    init(page: SubscriptionFeedPage) {
        self.page = page
    }

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { .disabled }
    func subscribe(channelID: String, accessToken: String) async throws {}
    func unsubscribe(subscriptionID: String, accessToken: String) async throws {}
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}

    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        receivedTokens.append(pageToken)
        return page
    }
}

// Class (not struct) so playlist/detail calls can be recorded for assertions;
// @unchecked Sendable is safe here because tests exercise calls sequentially.
// Deliberately does NOT implement `fetchSubscriptionFeed`, so calls exercise
// the protocol's default aggregation implementation under test.
private final class FeedScriptedAPI: YouTubeReading, @unchecked Sendable {
    let playlistIDs: [String]
    /// Pages served per playlist in call order; exhausted playlists serve empty pages.
    var pagesByPlaylist: [String: [(ids: [String], nextPageToken: String?)]] = [:]
    var detailsByID: [String: VideoSummary] = [:]
    private(set) var playlistCalls: [(playlistID: String, pageToken: String?)] = []
    private(set) var detailBatches: [[String]] = []
    private var pageCursors: [String: Int] = [:]

    init(playlistIDs: [String]) {
        self.playlistIDs = playlistIDs
    }

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { playlistIDs }

    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        playlistCalls.append((playlistID, pageToken))
        let pages = pagesByPlaylist[playlistID] ?? []
        let index = pageCursors[playlistID] ?? 0
        pageCursors[playlistID] = index + 1
        guard index < pages.count else { return (ids: [], nextPageToken: nil) }
        return pages[index]
    }

    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        detailBatches.append(ids)
        return ids.compactMap { detailsByID[$0] }
    }

    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { .disabled }
    func subscribe(channelID: String, accessToken: String) async throws {}
    func unsubscribe(subscriptionID: String, accessToken: String) async throws {}
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}
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
        XCTAssertEqual(feed.videos.map { $0.id }, ["long", "unknown"])
        XCTAssertNil(feed.nextPageToken)
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

    func testFetchFeedPropagatesNextPageTokenAndFilters() async throws {
        let api = StubYouTubeAPI(
            summaries: [summary(id: "long", duration: 600), summary(id: "short", duration: 30)],
            nextPageToken: "agg-tok"
        )
        let aggregator = HomeFeedAggregator(api: api)
        let page = try await aggregator.fetchFeed(accessToken: "tok")
        XCTAssertEqual(page.videos.map { $0.id }, ["long"])
        XCTAssertEqual(page.nextPageToken, "agg-tok")
    }

    func testFetchFeedThreadsPageTokenThroughToAPI() async throws {
        let api = PageRecordingAPI(page: SubscriptionFeedPage(videos: [], nextPageToken: "t2"))
        let aggregator = HomeFeedAggregator(api: api)
        _ = try await aggregator.fetchFeed(accessToken: "tok", pageToken: "t1")
        _ = try await aggregator.fetchFeed(accessToken: "tok")
        let tokens = await api.receivedTokens
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0], "t1")
        XCTAssertNil(tokens[1])
    }

    // MARK: - Default fetchSubscriptionFeed aggregation

    func testSubscriptionFeedChunksDetailFetchesAndConcatenatesInOrder() async throws {
        let pl1 = (0..<60).map { String(format: "p1-%03d", $0) }
        let pl2 = (0..<45).map { String(format: "p2-%03d", $0) }
        let api = FeedScriptedAPI(playlistIDs: ["PL1", "PL2"])
        api.pagesByPlaylist = [
            "PL1": [(ids: pl1, nextPageToken: nil)],
            "PL2": [(ids: pl2, nextPageToken: nil)]
        ]
        for id in pl1 + pl2 {
            api.detailsByID[id] = summary(id: id, duration: 600)
        }

        let page = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: nil)

        // 105 ids exceed videos.list's ~50-id cap: three batches, concatenated in order.
        XCTAssertEqual(api.detailBatches.map { $0.count }, [50, 50, 5])
        XCTAssertEqual(api.detailBatches.flatMap { $0 }, pl1 + pl2)
        XCTAssertEqual(page.videos.map { $0.id }, pl1 + pl2)
        XCTAssertNil(page.nextPageToken)
        XCTAssertEqual(api.playlistCalls.map { "\($0.playlistID)|\($0.pageToken ?? "nil")" }, ["PL1|nil", "PL2|nil"])
    }

    func testSubscriptionFeedCapsPagesPerPlaylistAndResumesFromToken() async throws {
        let firstPage = (0..<50).map { "pa-\($0)" }
        let secondPage = (50..<60).map { "pa-\($0)" }
        let thirdPage = (60..<65).map { "pa-\($0)" }
        let channelB = (0..<10).map { "pb-\($0)" }
        let api = FeedScriptedAPI(playlistIDs: ["PA", "PB"])
        api.pagesByPlaylist = [
            "PA": [
                (ids: firstPage, nextPageToken: "PA-t2"),
                (ids: secondPage, nextPageToken: "PA-t3"),
                (ids: thirdPage, nextPageToken: nil)
            ],
            "PB": [(ids: channelB, nextPageToken: nil)]
        ]
        for id in firstPage + secondPage + thirdPage + channelB {
            api.detailsByID[id] = summary(id: id, duration: 600)
        }

        // First call: PA consumes its two-page quota and pauses mid-playlist;
        // PB is left for the next call.
        let first = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: nil)
        XCTAssertEqual(first.videos.map { $0.id }, firstPage + secondPage)
        XCTAssertEqual(first.nextPageToken, "0|PA-t3")
        XCTAssertEqual(api.playlistCalls.map { "\($0.playlistID)|\($0.pageToken ?? "nil")" }, ["PA|nil", "PA|PA-t2"])

        // Resume: continues PA from its pending token, then walks PB fresh.
        let second = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: first.nextPageToken)
        XCTAssertEqual(second.videos.map { $0.id }, thirdPage + channelB)
        XCTAssertNil(second.nextPageToken)
        XCTAssertEqual(api.playlistCalls.map { "\($0.playlistID)|\($0.pageToken ?? "nil")" }, ["PA|nil", "PA|PA-t2", "PA|PA-t3", "PB|nil"])
    }

    func testMalformedPageTokenRestartsFromFirstPlaylist() async throws {
        let only = (0..<10).map { "pc-\($0)" }
        let api = FeedScriptedAPI(playlistIDs: ["PC"])
        api.pagesByPlaylist = ["PC": [(ids: only, nextPageToken: nil)]]
        for id in only {
            api.detailsByID[id] = summary(id: id, duration: 600)
        }

        let page = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: "garbage")

        XCTAssertEqual(page.videos.map { $0.id }, only)
        XCTAssertNil(page.nextPageToken)
        XCTAssertEqual(api.playlistCalls.map { "\($0.playlistID)|\($0.pageToken ?? "nil")" }, ["PC|nil"])
    }

    /// HB-030: a syntactically valid token whose playlist index is out of
    /// range (e.g. subscriptions shrank between sessions) restarts from the
    /// first playlist instead of crashing or skipping the walk.
    func testOutOfRangeResumeIndexRestartsFromFirstPlaylist() async throws {
        let ids = (0..<5).map { "pd-\($0)" }
        let api = FeedScriptedAPI(playlistIDs: ["PD1", "PD2"])
        api.pagesByPlaylist = [
            "PD1": [(ids: ids, nextPageToken: nil)],
            "PD2": [(ids: ids, nextPageToken: nil)]
        ]
        for id in ids {
            api.detailsByID[id] = summary(id: id, duration: 600)
        }

        let page = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: "9|stale-token")

        XCTAssertEqual(page.videos.map { $0.id }, ids + ids, "walk restarts from the first playlist")
        XCTAssertNil(page.nextPageToken)
        XCTAssertEqual(api.playlistCalls.map { "\($0.playlistID)|\($0.pageToken ?? "nil")" }, ["PD1|nil", "PD2|nil"])
    }

    func testEmptySubscriptionsReturnEmptyPageWithoutDetailCalls() async throws {
        let api = FeedScriptedAPI(playlistIDs: [])
        let page = try await api.fetchSubscriptionFeed(accessToken: "tok", pageToken: nil)
        XCTAssertTrue(page.videos.isEmpty)
        XCTAssertNil(page.nextPageToken)
        XCTAssertTrue(api.detailBatches.isEmpty)
    }
}
