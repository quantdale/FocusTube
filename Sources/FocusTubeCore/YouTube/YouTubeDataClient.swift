import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed YouTube Data API v3 client over `HTTPPerforming`. Pure request
/// building and error mapping are separated so they are deterministically
/// testable without network or credentials. No tokens are ever logged.
public struct YouTubeDataClient: YouTubeAPI {
    private let performer: HTTPPerforming
    private let baseURL: URL

    public init(performer: HTTPPerforming = URLSessionHTTPPerformer(), baseURL: URL = URL(string: "https://www.googleapis.com/youtube/v3")!) {
        self.performer = performer
        self.baseURL = baseURL
    }

    // MARK: - Endpoints

    public func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: [
            "part": "contentDetails",
            "mine": "true",
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try Self.decode(SubscriptionsResponse.self, from: data)
        return decoded.items.map { $0.contentDetails.relatedPlaylists.uploads }
    }

    public func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        var query: [String: String] = [
            "part": "contentDetails",
            "playlistId": playlistID,
            "maxResults": "50"
        ]
        if let pageToken, !pageToken.isEmpty {
            query["pageToken"] = pageToken
        }
        let request = try Self.buildRequest(baseURL: baseURL, path: "playlistItems", accessToken: accessToken, query: query)
        let data = try await perform(request)
        let decoded = try Self.decode(PlaylistItemsResponse.self, from: data)
        return (decoded.items.map { $0.contentDetails.videoId }, decoded.nextPageToken)
    }

    public func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos", accessToken: accessToken, query: [
            "part": "snippet,contentDetails",
            "id": ids.joined(separator: ",")
        ])
        let data = try await perform(request)
        let decoded = try Self.decode(VideosResponse.self, from: data)
        return decoded.items.map { item in
            VideoSummary(
                id: item.id,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                durationSeconds: VideoSummary.duration(from: item.contentDetails.duration),
                publishedAt: ISO8601DateFormatter().date(from: item.snippet.publishedAt),
                thumbnailURL: item.snippet.thumbnails.medium?.url,
                description: item.snippet.description,
                channelID: item.snippet.channelId
            )
        }
    }

    public func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        var query: [String: String] = [
            "part": "snippet",
            "q": query,
            "type": "video",
            "maxResults": "20"
        ]
        if let pageToken, !pageToken.isEmpty {
            query["pageToken"] = pageToken
        }
        let request = try Self.buildRequest(baseURL: baseURL, path: "search", accessToken: accessToken, query: query)
        let data = try await perform(request)
        let decoded = try Self.decode(SearchResponse.self, from: data)
        return (decoded.items.compactMap { $0.id.videoId }, decoded.nextPageToken)
    }

    // MARK: - Decoding

    /// Maps raw `DecodingError`s onto the typed `.decode` API error so callers
    /// never see untyped decoder internals (G3 acceptance).
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw YouTubeAPIError.decode
        }
    }

    // MARK: - Comments

    public func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage {
        var query: [String: String] = [
            "part": "snippet,replies",
            "videoId": videoID,
            "maxResults": "20",
            "textFormat": "plainText"
        ]
        if let pageToken, !pageToken.isEmpty {
            query["pageToken"] = pageToken
        }
        let request = try Self.buildRequest(baseURL: baseURL, path: "commentThreads", accessToken: accessToken, query: query)
        let data = try await perform(request)
        let decoded = try Self.decode(CommentThreadsResponse.self, from: data)
        let comments = decoded.items.map { item -> Comment in
            let top = item.snippet.topLevelComment
            let replies = (item.replies?.comments ?? []).map { rc in
                Comment(
                    id: rc.id,
                    author: rc.snippet.authorDisplayName,
                    text: rc.snippet.textDisplay,
                    likeCount: rc.snippet.likeCount ?? 0,
                    publishedAt: ISO8601DateFormatter().date(from: rc.snippet.publishedAt),
                    replyCount: 0
                )
            }
            return Comment(
                id: top.id,
                author: top.snippet.authorDisplayName,
                text: top.snippet.textDisplay,
                likeCount: top.snippet.likeCount ?? 0,
                publishedAt: ISO8601DateFormatter().date(from: top.snippet.publishedAt),
                replyCount: item.snippet.totalReplyCount ?? 0,
                replies: replies
            )
        }
        return CommentPage(comments: comments, nextPageToken: decoded.nextPageToken, commentsDisabled: false)
    }

    // MARK: - Account actions

    public func subscribe(channelID: String, accessToken: String) async throws {
        var request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "snippet": ["resourceId": ["kind": "youtube#channel", "channelId": channelID]]
        ])
        _ = try await perform(request)
    }

    public func unsubscribe(subscriptionID: String, accessToken: String) async throws {
        var request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: ["id": subscriptionID])
        request.httpMethod = "DELETE"
        _ = try await perform(request)
    }

    public func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos/rate", accessToken: accessToken, query: [
            "id": videoID,
            "rating": rating.rawValue
        ])
        var r = request
        r.httpMethod = "POST"
        _ = try await perform(r)
    }

    // MARK: - Comment mutation (DDV2-03)

    /// Creates a top-level comment via `commentThreads.insert` and returns the
    /// created comment as stored by YouTube. Text is validated before any
    /// network work; the request body carries `textOriginal` only.
    public func postTopLevelComment(videoID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedCommentText(text) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "commentThreads", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CommentThreadInsertBody(
            snippet: .init(
                videoId: videoID,
                topLevelComment: .init(snippet: .init(textOriginal: trimmed))
            )
        ))
        let data = try await perform(request)
        let decoded = try Self.decode(InsertedThreadResponse.self, from: data)
        return decoded.snippet.topLevelComment.normalizedComment
    }

    /// Creates a reply via `comments.insert`. `parentCommentID` must be an
    /// existing comment resource id; replying to a reply requires its TOP-LEVEL
    /// ancestor id per API semantics, which callers normalize before calling.
    public func postReply(parentCommentID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedCommentText(text) else { throw YouTubeAPIError.invalidInput }
        guard !parentCommentID.isEmpty else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "comments", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CommentInsertBody(
            snippet: .init(parentId: parentCommentID, textOriginal: trimmed)
        ))
        let data = try await perform(request)
        let decoded = try Self.decode(InsertedCommentResource.self, from: data)
        return decoded.normalizedComment
    }

    /// Looks up whether the authenticated user subscribes to `channelID` via a
    /// filtered `subscriptions.list` (`mine=true&forChannelId=`). Returns nil
    /// when the user is not subscribed.
    public func findMySubscription(channelID: String, accessToken: String) async throws -> SubscriptionLookup? {
        let request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: [
            "part": "id,snippet",
            "mine": "true",
            "forChannelId": channelID,
            "maxResults": "1"
        ])
        let data = try await perform(request)
        let decoded = try Self.decode(MySubscriptionsResponse.self, from: data)
        return decoded.items.first.map {
            SubscriptionLookup(subscriptionID: $0.id, channelTitle: $0.snippet.title)
        }
    }

    /// Reads the authenticated user's current rating for a video.
    public func fetchMyVideoRating(videoID: String, accessToken: String) async throws -> VideoRatingState {
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos/getRating", accessToken: accessToken, query: ["id": videoID])
        let data = try await perform(request)
        let decoded = try Self.decode(VideoRatingResponse.self, from: data)
        return decoded.items.first.flatMap { VideoRatingState(rawValue: $0.rating) } ?? .unspecified
    }

    /// Shared comment-text validation: non-empty after trimming, bounded to
    /// YouTube's documented 10,000-character `textOriginal` limit. Returns the
    /// trimmed text to submit.
    static func validatedCommentText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxCommentTextLength else { return nil }
        return trimmed
    }

    static let maxCommentTextLength = 10_000

    // MARK: - Execution / mapping

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await performer.data(for: request)
        } catch {
            throw YouTubeAPIError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.unknown(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.apiError(from: data, statusCode: http.statusCode)
        }
        return data
    }

    private static func apiError(from data: Data, statusCode: Int) -> YouTubeAPIError {
        if statusCode == 403,
           let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           decoded.error.errors.contains(where: { $0.reason == "commentsDisabled" }) {
            return .commentsDisabled
        }
        return mapError(statusCode)
    }

    public static func mapError(_ statusCode: Int) -> YouTubeAPIError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .quotaExceeded
        case 404: return .notFound
        default: return .unknown(status: statusCode)
        }
    }

    private static func buildRequest(baseURL: URL, path: String, accessToken: String, query: [String: String]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw YouTubeAPIError.unknown(status: -1)
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw YouTubeAPIError.unknown(status: -1) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// MARK: - Private decode models

private struct SubscriptionsResponse: Decodable {
    let items: [SubscriptionItem]
    struct SubscriptionItem: Decodable {
        let contentDetails: ContentDetails
        struct ContentDetails: Decodable {
            let relatedPlaylists: RelatedPlaylists
            struct RelatedPlaylists: Decodable {
                let uploads: String
            }
        }
    }
}

private struct PlaylistItemsResponse: Decodable {
    let nextPageToken: String?
    let items: [PlaylistItem]
    struct PlaylistItem: Decodable {
        let contentDetails: ContentDetails
        struct ContentDetails: Decodable {
            let videoId: String
        }
    }
}

private struct VideosResponse: Decodable {
    let items: [VideoItem]
    struct VideoItem: Decodable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
        struct Snippet: Decodable {
            let title: String
            let channelTitle: String
            let channelId: String?
            let publishedAt: String
            let description: String
            let thumbnails: Thumbnails
            struct Thumbnails: Decodable {
                let medium: Thumbnail?
                struct Thumbnail: Decodable {
                    let url: URL
                }
            }
        }
        struct ContentDetails: Decodable {
            let duration: String
        }
    }
}

private struct SearchResponse: Decodable {
    let nextPageToken: String?
    let items: [SearchItem]
    struct SearchItem: Decodable {
        let id: ID
        struct ID: Decodable {
            let videoId: String?
        }
    }
}

private struct ErrorEnvelope: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable {
        let errors: [ErrorItem]
        struct ErrorItem: Decodable {
            let reason: String
        }
    }
}

private struct CommentThreadsResponse: Decodable {
    let nextPageToken: String?
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let snippet: Snippet
        let replies: Replies?
        struct Snippet: Decodable {
            let topLevelComment: TopLevelComment
            let totalReplyCount: Int?
            struct TopLevelComment: Decodable {
                let id: String
                let snippet: CommentSnippet
            }
        }
        struct Replies: Decodable {
            let comments: [ReplyComment]
            struct ReplyComment: Decodable {
                let id: String
                let snippet: CommentSnippet
            }
        }
    }
    struct CommentSnippet: Decodable {
        let authorDisplayName: String
        let textDisplay: String
        let likeCount: Int?
        let publishedAt: String
    }
}

// MARK: - Mutation models (DDV2-03)

/// Request body for `commentThreads.insert` (top-level comment creation).
private struct CommentThreadInsertBody: Encodable {
    let snippet: Snippet
    struct Snippet: Encodable {
        let videoId: String
        let topLevelComment: TopLevel
        struct TopLevel: Encodable {
            let snippet: Text
            struct Text: Encodable { let textOriginal: String }
        }
    }
}

/// Request body for `comments.insert` (reply creation).
private struct CommentInsertBody: Encodable {
    let snippet: Snippet
    struct Snippet: Encodable {
        let parentId: String
        let textOriginal: String
    }
}

/// A freshly stored comment resource returned by either insert endpoint.
/// Fields Google may omit are optional with safe fallbacks; normalization
/// never fails on a well-formed-but-sparse resource.
private struct InsertedCommentResource: Decodable {
    let id: String
    let snippet: Snippet
    struct Snippet: Decodable {
        let authorDisplayName: String?
        let textDisplay: String?
        let textOriginal: String?
        let likeCount: Int?
        let publishedAt: String?
    }

    var normalizedComment: Comment {
        Comment(
            id: id,
            author: snippet.authorDisplayName ?? "",
            text: snippet.textDisplay ?? snippet.textOriginal ?? "",
            likeCount: snippet.likeCount ?? 0,
            publishedAt: snippet.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            replyCount: 0
        )
    }
}

/// Response of `commentThreads.insert`: a thread whose top-level comment is
/// the newly created one.
private struct InsertedThreadResponse: Decodable {
    let snippet: Snippet
    struct Snippet: Decodable {
        let topLevelComment: InsertedCommentResource
    }
}

/// Response of `subscriptions.list` filtered by mine+forChannelId.
private struct MySubscriptionsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let snippet: Snippet
        struct Snippet: Decodable {
            let title: String?
        }
    }
}

/// Response of `videos.getRating`.
private struct VideoRatingResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let videoId: String
        let rating: String
    }
}
