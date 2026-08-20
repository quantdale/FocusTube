import Foundation

/// Normalized comment (and optional replies) for the video page.
public struct Comment: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let author: String
    public let text: String
    public let likeCount: Int
    public let publishedAt: Date?
    public let replyCount: Int
    public let replies: [Comment]

    public init(
        id: String,
        author: String,
        text: String,
        likeCount: Int,
        publishedAt: Date?,
        replyCount: Int,
        replies: [Comment] = []
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.likeCount = likeCount
        self.publishedAt = publishedAt
        self.replyCount = replyCount
        self.replies = replies
    }
}

/// One page of a video's comment thread, including the disabled state.
public struct CommentPage: Sendable {
    public let comments: [Comment]
    public let nextPageToken: String?
    public let commentsDisabled: Bool

    public init(comments: [Comment], nextPageToken: String?, commentsDisabled: Bool) {
        self.comments = comments
        self.nextPageToken = nextPageToken
        self.commentsDisabled = commentsDisabled
    }

    public static let disabled = CommentPage(comments: [], nextPageToken: nil, commentsDisabled: true)
}
