import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed YouTube Data API error classes required by G3 acceptance.
public enum YouTubeAPIError: Error, Equatable, Sendable {
    case unauthorized
    case quotaExceeded
    case commentsDisabled
    case notFound
    case network
    case decode
    case unknown(status: Int)
}

/// Seam over `URLSession` so the client is deterministically testable.
public protocol HTTPPerforming: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default production performer. Wrapped in a stateless `Sendable` struct
/// because `URLSession` itself is not declared `Sendable` on every platform.
public struct URLSessionHTTPPerformer: HTTPPerforming {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// Boundary for the YouTube Data API v3. Media extraction (YouTubeKit) is never
/// coupled to this; the API client only needs an OAuth access token (or API
/// key) and returns normalized `VideoSummary` values.
public protocol YouTubeAPI: Sendable {
    /// Uploads-playlist IDs for the authenticated user's subscriptions.
    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String]
    /// Video IDs contained in a playlist (uploads playlist), plus the
    /// `playlistItems` continuation token for the next page, if any.
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?)
    /// Hydrated details for a set of video IDs.
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary]
    /// Video IDs from a search query, with optional pagination token.
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?)
    /// Comments for a video (top-level + their replies), or the disabled state.
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage
    /// Subscribe the authenticated user to a channel.
    func subscribe(channelID: String, accessToken: String) async throws
    /// Unsubscribe by subscription resource ID.
    func unsubscribe(subscriptionID: String, accessToken: String) async throws
    /// Set the authenticated user's rating for a video.
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws
    /// One page of the subscription feed as hydrated video summaries, with an
    /// opaque continuation token for explicit load-more.
    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage
}

/// One aggregated page of the subscription feed. `nextPageToken` is an opaque
/// continuation token owned by the API layer; callers pass it back verbatim to
/// fetch the next page.
public struct SubscriptionFeedPage: Sendable {
    public let videos: [VideoSummary]
    public let nextPageToken: String?

    public init(videos: [VideoSummary], nextPageToken: String?) {
        self.videos = videos
        self.nextPageToken = nextPageToken
    }
}

/// Treats an empty pagination token as absent.
private func normalizedToken(_ token: String?) -> String? {
    guard let token, !token.isEmpty else { return nil }
    return token
}

extension YouTubeAPI {
    /// Convenience overload fetching the first feed page.
    public func fetchSubscriptionFeed(accessToken: String) async throws -> SubscriptionFeedPage {
        try await fetchSubscriptionFeed(accessToken: accessToken, pageToken: nil)
    }

    /// Aggregates the subscriptions' uploads playlists into one hydrated feed
    /// page. Playlists are walked in subscription order; each visits at most
    /// two `playlistItems` pages per call to bound quota. The walk pauses at
    /// the first playlist that still has more pages when the cap is hit, and
    /// its position ("<playlistIndex>|<pageToken>") becomes the page's opaque
    /// continuation token; unrecognized or stale tokens restart from the first
    /// playlist. Detail hydration chunks ids into batches of 50 because
    /// `videos.list` rejects larger id= lists with HTTP 400.
    public func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        let playlists = try await fetchSubscriptionUploadsPlaylistIDs(accessToken: accessToken)

        var startIndex = playlists.startIndex
        var resumeToken: String?
        if let pageToken, !pageToken.isEmpty {
            let parts = pageToken.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, let index = Int(parts[0]), playlists.indices.contains(index) {
                startIndex = index
                resumeToken = parts[1].isEmpty ? nil : String(parts[1])
            }
        }

        var ids: [String] = []
        var continuation: String?
        for index in startIndex..<playlists.endIndex {
            var cursor = index == startIndex ? resumeToken : nil
            var pagesFetched = 0
            repeat {
                let page = try await fetchPlaylistVideoIDs(playlistID: playlists[index], accessToken: accessToken, pageToken: cursor)
                ids.append(contentsOf: page.ids)
                pagesFetched += 1
                cursor = normalizedToken(page.nextPageToken)
            } while cursor != nil && pagesFetched < 2
            if let next = cursor {
                continuation = "\(index)|\(next)"
                break
            }
        }

        guard !ids.isEmpty else { return SubscriptionFeedPage(videos: [], nextPageToken: continuation) }

        var summaries: [VideoSummary] = []
        var batch: [String] = []
        for id in ids {
            batch.append(id)
            if batch.count == 50 {
                summaries.append(contentsOf: try await fetchVideoDetails(ids: batch, accessToken: accessToken))
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            summaries.append(contentsOf: try await fetchVideoDetails(ids: batch, accessToken: accessToken))
        }
        return SubscriptionFeedPage(videos: summaries, nextPageToken: continuation)
    }
}
