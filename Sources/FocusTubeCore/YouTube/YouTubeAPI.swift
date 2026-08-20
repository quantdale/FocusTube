import Foundation

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

extension URLSession: HTTPPerforming {}

/// Boundary for the YouTube Data API v3. Media extraction (YouTubeKit) is never
/// coupled to this; the API client only needs an OAuth access token (or API
/// key) and returns normalized `VideoSummary` values.
public protocol YouTubeAPI: Sendable {
    /// Uploads-playlist IDs for the authenticated user's subscriptions.
    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String]
    /// Video IDs contained in a playlist (uploads playlist).
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String]
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
    /// Convenience: subscription feed as hydrated video summaries.
    func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary]
}

extension YouTubeAPI {
    public func fetchSubscriptionFeed(accessToken: String) async throws -> [VideoSummary] {
        let playlists = try await fetchSubscriptionUploadsPlaylistIDs(accessToken: accessToken)
        var ids: [String] = []
        for playlist in playlists {
            ids.append(contentsOf: try await fetchPlaylistVideoIDs(playlistID: playlist, accessToken: accessToken))
        }
        guard !ids.isEmpty else { return [] }
        return try await fetchVideoDetails(ids: ids, accessToken: accessToken)
    }
}
