import XCTest
@testable import FocusTubeCore

// Class (not struct) so action methods can record invocations for assertions;
// @unchecked Sendable is safe here because tests exercise calls sequentially.
private final class FullStubAPI: YouTubeAPI, @unchecked Sendable {
    var commentsPage: CommentPage = .disabled
    var commentsThrows: YouTubeAPIError?
    var subscribedChannel: String?
    var ratedVideo: (String, VideoRating)?
    var actionThrows: YouTubeAPIError?

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String] { [] }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> ([String], String?) { ([], nil) }
    func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary] { [] }

    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage {
        if let error = commentsThrows { throw error }
        return commentsPage
    }
    func subscribe(channelID: String, accessToken: String) async throws {
        if let error = actionThrows { throw error }
        subscribedChannel = channelID
    }
    func unsubscribe(subscriptionID: String, accessToken: String) async throws {
        if let error = actionThrows { throw error }
    }
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {
        if let error = actionThrows { throw error }
        ratedVideo = (videoID, rating)
    }
}

final class VideoActionsTests: XCTestCase {
    func testCommentsDisabledState() async throws {
        let api = FullStubAPI(commentsPage: .disabled)
        let service = CommentsService(api: api)
        let page = try await service.comments(videoID: "v", accessToken: "tok")
        XCTAssertTrue(page.commentsDisabled)
        XCTAssertTrue(page.comments.isEmpty)
    }

    func testCommentsReturnsThreadsWithReplies() async throws {
        let comment = Comment(
            id: "c1",
            author: "Alice",
            text: "Great",
            likeCount: 3,
            publishedAt: nil,
            replyCount: 1,
            replies: [Comment(id: "r1", author: "Bob", text: "Reply", likeCount: 0, publishedAt: nil, replyCount: 0)]
        )
        let api = FullStubAPI(commentsPage: CommentPage(comments: [comment], nextPageToken: "next", commentsDisabled: false))
        let service = CommentsService(api: api)
        let page = try await service.comments(videoID: "v", accessToken: "tok")
        XCTAssertFalse(page.commentsDisabled)
        XCTAssertEqual(page.comments.count, 1)
        XCTAssertEqual(page.comments.first?.replies.count, 1)
        XCTAssertEqual(page.nextPageToken, "next")
    }

    func testCommentsDisabledErrorPropagates() async {
        let api = FullStubAPI(commentsThrows: .commentsDisabled)
        let service = CommentsService(api: api)
        do {
            _ = try await service.comments(videoID: "v", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .commentsDisabled)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSubscribeAndRate() async throws {
        let api = FullStubAPI()
        let actions = AccountActionsService(api: api)
        try await actions.subscribe(channelID: "UC123", accessToken: "tok")
        try await actions.rate(videoID: "v", rating: .like, accessToken: "tok")
        XCTAssertEqual(api.subscribedChannel, "UC123")
        XCTAssertEqual(api.ratedVideo?.0, "v")
        XCTAssertEqual(api.ratedVideo?.1, .like)
    }

    func testActionQuotaError() async {
        let api = FullStubAPI(actionThrows: .quotaExceeded)
        let actions = AccountActionsService(api: api)
        do {
            try await actions.subscribe(channelID: "UC123", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
