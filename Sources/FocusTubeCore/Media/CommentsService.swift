import Foundation

/// Thin wrapper over the comments endpoint so the disabled state is handled
/// explicitly by callers rather than swallowed as a generic error.
public struct CommentsService {
    private let api: YouTubeAPI

    public init(api: YouTubeAPI) {
        self.api = api
    }

    public func comments(videoID: String, accessToken: String, pageToken: String? = nil) async throws -> CommentPage {
        try await api.fetchComments(videoID: videoID, accessToken: accessToken, pageToken: pageToken)
    }
}
