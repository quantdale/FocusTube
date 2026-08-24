import Foundation

/// Thin wrapper over the comments endpoints. Reads, the explicit disabled
/// state, AND the mutation paths (top-level post / reply) flow through here so
/// the UI never constructs raw API requests. Input is validated before any
/// network work; failures are typed.
public struct CommentsService: Sendable {
    private let api: YouTubeAPI

    /// YouTube's documented maximum for comment `textOriginal`.
    public static let maxTextLength = 10_000

    public init(api: YouTubeAPI) {
        self.api = api
    }

    public func comments(videoID: String, accessToken: String, pageToken: String? = nil) async throws -> CommentPage {
        try await api.fetchComments(videoID: videoID, accessToken: accessToken, pageToken: pageToken)
    }

    /// Creates a top-level comment. Returns the stored comment so the caller
    /// can insert it into the visible tree without a refetch.
    public func post(videoID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedText(text) else {
            throw YouTubeAPIError.invalidInput
        }
        return try await api.postTopLevelComment(videoID: videoID, text: trimmed, accessToken: accessToken)
    }

    /// Creates a reply under `parentCommentID`. Returns the stored reply.
    public func reply(to parentCommentID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedText(text), !parentCommentID.isEmpty else {
            throw YouTubeAPIError.invalidInput
        }
        return try await api.postReply(parentCommentID: parentCommentID, text: trimmed, accessToken: accessToken)
    }

    /// Canonical validation: non-empty after trimming, within the documented
    /// length bound. Returns the trimmed text to submit.
    public static func validatedText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxTextLength else { return nil }
        return trimmed
    }
}
