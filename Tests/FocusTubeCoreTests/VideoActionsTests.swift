import XCTest
@testable import FocusTubeCore

// Class (not struct) so action methods can record invocations for assertions;
// @unchecked Sendable is safe here because tests exercise calls sequentially.
private final class FullStubAPI: YouTubeAPI, @unchecked Sendable {
    var commentsPage: CommentPage
    var commentsThrows: YouTubeAPIError?
    var subscribedChannel: String?
    var ratedVideo: (String, VideoRating)?
    var actionThrows: YouTubeAPIError?

    init(
        commentsPage: CommentPage = .disabled,
        commentsThrows: YouTubeAPIError? = nil,
        subscribedChannel: String? = nil,
        ratedVideo: (String, VideoRating)? = nil,
        actionThrows: YouTubeAPIError? = nil
    ) {
        self.commentsPage = commentsPage
        self.commentsThrows = commentsThrows
        self.subscribedChannel = subscribedChannel
        self.ratedVideo = ratedVideo
        self.actionThrows = actionThrows
    }

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { [] }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { [] }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { ([], nil) }
    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        SubscriptionFeedPage(videos: [], nextPageToken: nil)
    }

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
        lastUnsubscribedSubscriptionID = subscriptionID
    }
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {
        if let error = actionThrows { throw error }
        ratedVideo = (videoID, rating)
    }

    var postedComment: (videoID: String, text: String)?
    var postedReply: (parentID: String, text: String)?
    var storedCommentToReturn: Comment?
    var mySubscription: SubscriptionLookup?
    var myRatingState: VideoRatingState = .unspecified
    private(set) var lastUnsubscribedSubscriptionID: String?

    func postTopLevelComment(videoID: String, text: String, accessToken: String) async throws -> Comment {
        if let error = actionThrows { throw error }
        postedComment = (videoID, text)
        return storedCommentToReturn ?? Comment(id: "new-c", author: "Me", text: text, likeCount: 0, publishedAt: nil, replyCount: 0)
    }

    func postReply(parentCommentID: String, text: String, accessToken: String) async throws -> Comment {
        if let error = actionThrows { throw error }
        postedReply = (parentCommentID, text)
        return storedCommentToReturn ?? Comment(id: "new-r", author: "Me", text: text, likeCount: 0, publishedAt: nil, replyCount: 0)
    }

    func findMySubscription(channelID: String, accessToken: String) async throws -> SubscriptionLookup? {
        if let error = actionThrows { throw error }
        return mySubscription
    }

    func fetchMyVideoRating(videoID: String, accessToken: String) async throws -> VideoRatingState {
        if let error = actionThrows { throw error }
        return myRatingState
    }

    // HB-019: no inherited protocol-extension defaults remain; playlist
    // endpoints are stubbed explicitly so full conformance stays honest.
    func fetchMyPlaylists(accessToken: String) async throws -> [PlaylistSummary] { [] }
    func fetchPlaylistItems(playlistID: String, accessToken: String) async throws -> [PlaylistItemSummary] { [] }
    func addToPlaylist(playlistID: String, videoID: String, accessToken: String) async throws {}
    func removeFromPlaylist(playlistItemID: String, accessToken: String) async throws {}
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

    // MARK: - DDV2-03: comment mutation service

    func testPostValidatesTextBeforeNetworkAndTrimsInput() async throws {
        let api = FullStubAPI()
        let service = CommentsService(api: api)
        do {
            _ = try await service.post(videoID: "v", text: "   ", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .invalidInput)
        } catch { XCTFail("unexpected: \(error)") }
        XCTAssertNil(api.postedComment, "invalid input must never reach the API")

        let stored = try await service.post(videoID: "v", text: "  Hello world  ", accessToken: "tok")
        XCTAssertEqual(stored.text, "Hello world")
        XCTAssertEqual(api.postedComment?.videoID, "v")
        XCTAssertEqual(api.postedComment?.text, "Hello world")
    }

    func testReplyValidatesParentAndText() async throws {
        let api = FullStubAPI()
        let service = CommentsService(api: api)
        do {
            _ = try await service.reply(to: "", text: "x", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .invalidInput)
        } catch { XCTFail("unexpected: \(error)") }
        XCTAssertNil(api.postedReply)

        _ = try await service.reply(to: "c1", text: "reply", accessToken: "tok")
        XCTAssertEqual(api.postedReply?.parentID, "c1")
    }

    func testMutationErrorSurfacesTypedFailure() async throws {
        let api = FullStubAPI(actionThrows: .quotaExceeded)
        let service = CommentsService(api: api)
        do {
            _ = try await service.post(videoID: "v", text: "hi", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .quotaExceeded)
        } catch { XCTFail("unexpected: \(error)") }
    }

    // MARK: - DDV2-03: account state lookups

    func testUnsubscribeResolvesSubscriptionResourceIDFirst() async throws {
        let api = FullStubAPI()
        api.mySubscription = SubscriptionLookup(subscriptionID: "SUB9", channelTitle: "Chan")
        let actions = AccountActionsService(api: api)
        try await actions.unsubscribe(channelID: "UC777", accessToken: "tok")
        XCTAssertEqual(api.lastUnsubscribedSubscriptionID, "SUB9", "unsubscribe must target the resolved resource id")
    }

    func testUnsubscribeWithoutSubscriptionThrowsNotFound() async throws {
        let api = FullStubAPI()
        api.mySubscription = nil
        let actions = AccountActionsService(api: api)
        do {
            try await actions.unsubscribe(channelID: "UC777", accessToken: "tok")
            XCTFail()
        } catch let error as YouTubeAPIError {
            XCTAssertEqual(error, .notFound)
        } catch { XCTFail("unexpected: \(error)") }
    }

    func testRatingStateLookupIsAuthoritative() async throws {
        let api = FullStubAPI()
        api.myRatingState = .like
        let actions = AccountActionsService(api: api)
        let state = try await actions.ratingState(videoID: "v1", accessToken: "tok")
        XCTAssertEqual(state, VideoRatingState.like)
    }
}
