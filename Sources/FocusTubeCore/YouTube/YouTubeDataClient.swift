import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed YouTube Data API v3 client over `HTTPPerforming`. Pure request
/// building and error mapping are separated so they are deterministically
/// testable without network or credentials. No tokens are ever logged.
///
/// List decoding is deliberately tolerant at the ITEM level (HB-016): one
/// anomalous element skips with a reported count instead of failing the whole
/// page, but a list where EVERY item is malformed still throws `.decode` so
/// systematic shape drift surfaces as an error rather than a silent empty
/// state. Top-level envelope fields stay strict.
public struct YouTubeDataClient: YouTubeAPI {
    private let performer: HTTPPerforming
    private let baseURL: URL
    /// Observability seam for skipped malformed items (HB-016 non-silent
    /// requirement). Core stays platform-neutral; production wires an
    /// `os.Logger` reporter at composition time.
    private let onItemsSkipped: (@Sendable (_ endpoint: String, _ count: Int) -> Void)?

    public init(
        performer: HTTPPerforming = URLSessionHTTPPerformer(),
        baseURL: URL = URL(string: "https://www.googleapis.com/youtube/v3")!,
        onItemsSkipped: (@Sendable (_ endpoint: String, _ count: Int) -> Void)? = nil
    ) {
        self.performer = performer
        self.baseURL = baseURL
        self.onItemsSkipped = onItemsSkipped
    }

    // MARK: - Endpoints

    public func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: [
            "part": "contentDetails",
            "mine": "true",
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try self.decode(SubscriptionsResponse.self, from: data)
        return try self.resolved(decoded.items, endpoint: "subscriptions").map { $0.contentDetails.relatedPlaylists.uploads }
    }

    public func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        guard let playlistID = Self.validatedResourceID(playlistID) else { throw YouTubeAPIError.invalidInput }
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
        let decoded = try self.decode(PlaylistItemsResponse.self, from: data)
        let items = try self.resolved(decoded.items, endpoint: "playlistItems")
        return (items.map { $0.contentDetails.videoId }, decoded.nextPageToken)
    }

    public func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos", accessToken: accessToken, query: [
            "part": "snippet,contentDetails",
            "id": ids.joined(separator: ",")
        ])
        let data = try await perform(request)
        let decoded = try self.decode(VideosResponse.self, from: data)
        return try self.resolved(decoded.items, endpoint: "videos").map { item in
            VideoSummary(
                id: item.id,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                durationSeconds: VideoSummary.duration(from: item.contentDetails.duration),
                publishedAt: APIDate.date(item.snippet.publishedAt),
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
        let decoded = try self.decode(SearchResponse.self, from: data)
        let items = try self.resolved(decoded.items, endpoint: "search")
        return (items.compactMap { $0.id.videoId }, decoded.nextPageToken)
    }

    // MARK: - Decoding

    /// Wraps one list element so a single anomalous item cannot fail the whole
    /// page (HB-016). Deliberate tradeoff recorded in the H3 audit ledger:
    /// partial content plus a reported skip count beats a full-surface error
    /// when Google emits an unexpected shape for individual resources.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw YouTubeAPIError.decode
        }
    }

    /// Unwraps tolerated items, enforcing the two truthfulness bounds:
    /// every-item-malformed still throws `.decode`, and any partial skip is
    /// reported through the injected observer instead of vanishing.
    private func resolved<T>(_ wrapped: [TolerantItem<T>], endpoint: String) throws -> [T] {
        let values = wrapped.compactMap(\.value)
        if !wrapped.isEmpty, values.isEmpty {
            throw YouTubeAPIError.decode
        }
        let skipped = wrapped.count - values.count
        if skipped > 0 {
            onItemsSkipped?("youtube.\(endpoint)", skipped)
        }
        return values
    }

    // MARK: - Comments

    public func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage {
        guard let videoID = Self.validatedResourceID(videoID) else { throw YouTubeAPIError.invalidInput }
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
        let decoded = try self.decode(CommentThreadsResponse.self, from: data)
        let comments = try self.resolved(decoded.items, endpoint: "commentThreads").map { item -> Comment in
            let top = item.snippet.topLevelComment
            let replies = (item.replies?.comments ?? []).map { rc in
                Comment(
                    id: rc.id,
                    author: rc.snippet.authorDisplayName,
                    text: rc.snippet.textDisplay,
                    likeCount: rc.snippet.likeCount ?? 0,
                    publishedAt: APIDate.date(rc.snippet.publishedAt),
                    replyCount: 0
                )
            }
            return Comment(
                id: top.id,
                author: top.snippet.authorDisplayName,
                text: top.snippet.textDisplay,
                likeCount: top.snippet.likeCount ?? 0,
                publishedAt: APIDate.date(top.snippet.publishedAt),
                replyCount: item.snippet.totalReplyCount ?? 0,
                replies: replies
            )
        }
        return CommentPage(comments: comments, nextPageToken: decoded.nextPageToken, commentsDisabled: false)
    }

    // MARK: - Account actions

    public func subscribe(channelID: String, accessToken: String) async throws {
        guard let channelID = Self.validatedResourceID(channelID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "snippet": ["resourceId": ["kind": "youtube#channel", "channelId": channelID]]
        ])
        _ = try await perform(request)
    }

    public func unsubscribe(subscriptionID: String, accessToken: String) async throws {
        guard let subscriptionID = Self.validatedResourceID(subscriptionID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: ["id": subscriptionID])
        request.httpMethod = "DELETE"
        _ = try await perform(request)
    }

    public func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {
        guard let videoID = Self.validatedResourceID(videoID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "videos/rate", accessToken: accessToken, query: [
            "id": videoID,
            "rating": rating.rawValue
        ])
        request.httpMethod = "POST"
        _ = try await perform(request)
    }

    // MARK: - Comment mutation (DDV2-03)

    /// Creates a top-level comment via `commentThreads.insert` and returns the
    /// created comment as stored by YouTube. Text is validated before any
    /// network work; the request body carries `textOriginal` only.
    public func postTopLevelComment(videoID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedCommentText(text) else { throw YouTubeAPIError.invalidInput }
        guard let videoID = Self.validatedResourceID(videoID) else { throw YouTubeAPIError.invalidInput }
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
        let decoded = try self.decode(InsertedThreadResponse.self, from: data)
        return decoded.snippet.topLevelComment.normalizedComment
    }

    /// Creates a reply via `comments.insert`. `parentCommentID` must be an
    /// existing comment resource id; replying to a reply requires its TOP-LEVEL
    /// ancestor id per API semantics, which callers normalize before calling.
    public func postReply(parentCommentID: String, text: String, accessToken: String) async throws -> Comment {
        guard let trimmed = Self.validatedCommentText(text) else { throw YouTubeAPIError.invalidInput }
        guard let parentCommentID = Self.validatedResourceID(parentCommentID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "comments", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CommentInsertBody(
            snippet: .init(parentId: parentCommentID, textOriginal: trimmed)
        ))
        let data = try await perform(request)
        let decoded = try self.decode(InsertedCommentResource.self, from: data)
        return decoded.normalizedComment
    }

    /// Looks up whether the authenticated user subscribes to `channelID` via a
    /// filtered `subscriptions.list` (`mine=true&forChannelId=`). Returns nil
    /// when the user is not subscribed.
    public func findMySubscription(channelID: String, accessToken: String) async throws -> SubscriptionLookup? {
        guard let channelID = Self.validatedResourceID(channelID) else { throw YouTubeAPIError.invalidInput }
        let request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: [
            "part": "id,snippet",
            "mine": "true",
            "forChannelId": channelID,
            "maxResults": "1"
        ])
        let data = try await perform(request)
        let decoded = try self.decode(MySubscriptionsResponse.self, from: data)
        let items = try self.resolved(decoded.items, endpoint: "subscriptions.lookup")
        return items.first.map {
            SubscriptionLookup(subscriptionID: $0.id, channelTitle: $0.snippet.title)
        }
    }

    /// Reads the authenticated user's current rating for a video.
    public func fetchMyVideoRating(videoID: String, accessToken: String) async throws -> VideoRatingState {
        guard let videoID = Self.validatedResourceID(videoID) else { throw YouTubeAPIError.invalidInput }
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos/getRating", accessToken: accessToken, query: ["id": videoID])
        let data = try await perform(request)
        let decoded = try self.decode(VideoRatingResponse.self, from: data)
        let items = try self.resolved(decoded.items, endpoint: "videos.getRating")
        return items.first.flatMap { VideoRatingState(rawValue: $0.rating) } ?? .unspecified
    }

    // MARK: - Supported playlists (DDV2-08, bounded subset)

    /// First page of the user's own playlists (max 50 — personal scale).
    public func fetchMyPlaylists(accessToken: String) async throws -> [PlaylistSummary] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "playlists", accessToken: accessToken, query: [
            "part": "snippet,contentDetails",
            "mine": "true",
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try self.decode(MyPlaylistsResponse.self, from: data)
        return try self.resolved(decoded.items, endpoint: "playlists").map {
            PlaylistSummary(id: $0.id, title: $0.snippet.title, privacyStatus: $0.status?.privacyStatus, itemCount: $0.contentDetails.itemCount ?? 0)
        }
    }

    /// Items of one playlist with the resource ids needed for removal.
    public func fetchPlaylistItems(playlistID: String, accessToken: String) async throws -> [PlaylistItemSummary] {
        guard let playlistID = Self.validatedResourceID(playlistID) else { throw YouTubeAPIError.invalidInput }
        let request = try Self.buildRequest(baseURL: baseURL, path: "playlistItems", accessToken: accessToken, query: [
            "part": "snippet,contentDetails",
            "playlistId": playlistID,
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try self.decode(PlaylistItemsDetailResponse.self, from: data)
        return try self.resolved(decoded.items, endpoint: "playlistItems.detail").map {
            PlaylistItemSummary(
                playlistItemID: $0.id,
                videoID: $0.contentDetails.videoId,
                title: $0.snippet.title,
                channelTitle: $0.snippet.videoOwnerChannelTitle ?? $0.snippet.channelTitle
            )
        }
    }

    /// Appends a video to a user-owned playlist (playlistItems.insert).
    public func addToPlaylist(playlistID: String, videoID: String, accessToken: String) async throws {
        guard let playlistID = Self.validatedResourceID(playlistID),
              let videoID = Self.validatedResourceID(videoID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "playlistItems", accessToken: accessToken, query: ["part": "snippet"])
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlaylistItemInsertBody(
            snippet: .init(playlistId: playlistID, resourceId: .init(kind: "youtube#video", videoId: videoID))
        ))
        _ = try await perform(request)
    }

    /// Removes an item by its playlistItem resource id.
    public func removeFromPlaylist(playlistItemID: String, accessToken: String) async throws {
        guard let playlistItemID = Self.validatedResourceID(playlistItemID) else { throw YouTubeAPIError.invalidInput }
        var request = try Self.buildRequest(baseURL: baseURL, path: "playlistItems", accessToken: accessToken, query: ["id": playlistItemID])
        request.httpMethod = "DELETE"
        _ = try await perform(request)
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

    /// Shared pre-wire guard for resource ids (HB-018). Ids normally originate
    /// from API responses, but callers may reconstruct or persist them; garbage
    /// input must surface as typed `.invalidInput` instead of an opaque wire
    /// error, uniformly across read/mutation paths.
    static func validatedResourceID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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

    /// Legacy `errors[].reason` strings Google emits for quota-family denials.
    private static let quotaReasons: Set<String> = [
        "quotaExceeded",
        "dailyLimitExceeded",
        "rateLimitExceeded",
        "userRateLimitExceeded"
    ]

    /// Legacy `errors[].reason` strings for permanent permission denials.
    private static let permissionReasons: Set<String> = [
        "forbidden",
        "insufficientPermissions"
    ]

    private static func apiError(from data: Data, statusCode: Int) -> YouTubeAPIError {
        guard statusCode == 403 else { return mapError(statusCode) }
        // HB-015 taxonomy. Evidence order:
        // 1. legacy reason "commentsDisabled" keeps its dedicated product case;
        // 2. recognized quota reasons (legacy) or canonical status
        //    RESOURCE_EXHAUSTED stay retryable `.quotaExceeded`;
        // 3. recognized permission reasons or canonical status PERMISSION_DENIED
        //    become permanent `.forbidden` (distinct non-retry copy);
        // 4. DELIBERATE fallback: unparseable/unrecognized 403 bodies remain
        //    `.quotaExceeded`. Quota is the overwhelmingly likeliest 403 cause
        //    for this app's endpoints and the only classification whose retry
        //    guidance is safe when the true cause is unknown.
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let reasons = Set((envelope?.error.errors ?? []).compactMap(\.reason))
        if reasons.contains("commentsDisabled") {
            return .commentsDisabled
        }
        let status = envelope?.error.status?.uppercased()
        if !reasons.isDisjoint(with: quotaReasons) || status == "RESOURCE_EXHAUSTED" {
            return .quotaExceeded
        }
        if !reasons.isDisjoint(with: permissionReasons) || status == "PERMISSION_DENIED" {
            return .forbidden
        }
        return .quotaExceeded
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

/// Cached RFC3339 parsers (HB-021). Formatter allocation used to happen inside
/// per-item decode maps, and the default option set silently parsed
/// fractional-second timestamps to nil. Both shapes now parse through shared
/// instances; ISO8601DateFormatter is documented thread-safe.
enum APIDate {
    /// ISO8601DateFormatter is documented thread-safe; `nonisolated(unsafe)`
    /// satisfies Swift 6 strict concurrency for these shared instances.
    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ raw: String) -> Date? {
        fractional.date(from: raw) ?? plain.date(from: raw)
    }
}

/// Wraps one list element so a single anomalous item cannot fail the whole
/// page decode (HB-016). File-private decode-model support type.
private struct TolerantItem<Item: Decodable>: Decodable {
    let value: Item?

    init(from decoder: Decoder) throws {
        value = try? Item(from: decoder)
    }
}

/// One subscriptions.list row. Fields Google may omit are optional; a row that
/// cannot decode at all is skipped by the client's tolerant item policy.
private struct SubscriptionItem: Decodable {
    let contentDetails: ContentDetails
    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists
        struct RelatedPlaylists: Decodable {
            let uploads: String
        }
    }
}

private struct SubscriptionsResponse: Decodable {
    let items: [TolerantItem<SubscriptionItem>]
}

private struct PlaylistRow: Decodable {
    let contentDetails: ContentDetails
    struct ContentDetails: Decodable {
        let videoId: String
    }
}

private struct PlaylistItemsResponse: Decodable {
    let nextPageToken: String?
    let items: [TolerantItem<PlaylistRow>]
}

private struct VideoRow: Decodable {
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

private struct VideosResponse: Decodable {
    let items: [TolerantItem<VideoRow>]
}

private struct SearchRow: Decodable {
    let id: ID
    struct ID: Decodable {
        let videoId: String?
    }
}

private struct SearchResponse: Decodable {
    let nextPageToken: String?
    let items: [TolerantItem<SearchRow>]
}

private struct ErrorEnvelope: Decodable {
    let error: ErrorBody
    struct ErrorBody: Decodable {
        let errors: [ErrorItem]?
        let status: String?
        struct ErrorItem: Decodable {
            let reason: String?
        }
    }
}

private struct CommentThreadRow: Decodable {
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
    struct CommentSnippet: Decodable {
        let authorDisplayName: String
        let textDisplay: String
        let likeCount: Int?
        let publishedAt: String
    }
}

private struct CommentThreadsResponse: Decodable {
    let nextPageToken: String?
    let items: [TolerantItem<CommentThreadRow>]
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
            publishedAt: snippet.publishedAt.flatMap { APIDate.date($0) },
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

/// Row of `subscriptions.list` filtered by mine+forChannelId.
private struct MySubscriptionRow: Decodable {
    let id: String
    let snippet: Snippet
    struct Snippet: Decodable {
        let title: String?
    }
}

private struct MySubscriptionsResponse: Decodable {
    let items: [TolerantItem<MySubscriptionRow>]
}

/// Response of `videos.getRating`.
private struct VideoRatingRow: Decodable {
    let videoId: String
    let rating: String
}

private struct VideoRatingResponse: Decodable {
    let items: [TolerantItem<VideoRatingRow>]
}

/// Row of `playlists.list` filtered to mine.
private struct MyPlaylistRow: Decodable {
    let id: String
    let snippet: Snippet
    let status: Status?
    let contentDetails: ContentDetails
    struct Snippet: Decodable {
        let title: String
    }
    struct Status: Decodable {
        let privacyStatus: String?
    }
    struct ContentDetails: Decodable {
        let itemCount: Int?
    }
}

private struct MyPlaylistsResponse: Decodable {
    let items: [TolerantItem<MyPlaylistRow>]
}

/// Detailed `playlistItems.list` row including snippet titles.
private struct PlaylistItemDetailRow: Decodable {
    let id: String
    let snippet: Snippet
    let contentDetails: ContentDetails
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
        let videoOwnerChannelTitle: String?
    }
    struct ContentDetails: Decodable {
        let videoId: String
    }
}

private struct PlaylistItemsDetailResponse: Decodable {
    let items: [TolerantItem<PlaylistItemDetailRow>]
}

/// Request body for `playlistItems.insert`.
private struct PlaylistItemInsertBody: Encodable {
    let snippet: Snippet
    struct Snippet: Encodable {
        let playlistId: String
        let resourceId: ResourceID
    }
    struct ResourceID: Encodable {
        let kind: String
        let videoId: String
    }
}
