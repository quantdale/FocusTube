import Foundation

/// Supported authenticated account actions. Each is a single typed call over the
/// `YouTubeAPI` boundary so mutation logic stays testable and decoupled from UI.
public struct AccountActionsService: Sendable {
    private let api: YouTubeAPI

    public init(api: YouTubeAPI) {
        self.api = api
    }

    public func subscribe(channelID: String, accessToken: String) async throws {
        try await api.subscribe(channelID: channelID, accessToken: accessToken)
    }

    public func unsubscribe(subscriptionID: String, accessToken: String) async throws {
        try await api.unsubscribe(subscriptionID: subscriptionID, accessToken: accessToken)
    }

    public func rate(videoID: String, rating: VideoRating, accessToken: String) async throws {
        try await api.rateVideo(videoID: videoID, rating: rating, accessToken: accessToken)
    }

    /// Removes any existing rating (like/dislike) from a video.
    public func removeRating(videoID: String, accessToken: String) async throws {
        try await api.rateVideo(videoID: videoID, rating: .none, accessToken: accessToken)
    }

    /// The user's current subscription state for a channel, carrying the
    /// resource id required for a truthful unsubscribe. nil = not subscribed.
    /// Callers must never infer state from prior button taps — this is the
    /// only authoritative lookup.
    public func subscriptionState(channelID: String, accessToken: String) async throws -> SubscriptionLookup? {
        try await api.findMySubscription(channelID: channelID, accessToken: accessToken)
    }

    /// Unsubscribes using the channel id by first resolving the subscription
    /// resource id; throws notFound when the user is not subscribed.
    public func unsubscribe(channelID: String, accessToken: String) async throws {
        guard let lookup = try await subscriptionState(channelID: channelID, accessToken: accessToken) else {
            throw YouTubeAPIError.notFound
        }
        try await unsubscribe(subscriptionID: lookup.subscriptionID, accessToken: accessToken)
    }

    /// The user's current rating state for a video (authoritative read).
    public func ratingState(videoID: String, accessToken: String) async throws -> VideoRatingState {
        try await api.fetchMyVideoRating(videoID: videoID, accessToken: accessToken)
    }

    // MARK: - Bounded supported-playlists surface (DDV2-08)

    public func playlists(accessToken: String) async throws -> [PlaylistSummary] {
        try await api.fetchMyPlaylists(accessToken: accessToken)
    }

    public func playlistItems(playlistID: String, accessToken: String) async throws -> [PlaylistItemSummary] {
        try await api.fetchPlaylistItems(playlistID: playlistID, accessToken: accessToken)
    }

    public func addToPlaylist(playlistID: String, videoID: String, accessToken: String) async throws {
        try await api.addToPlaylist(playlistID: playlistID, videoID: videoID, accessToken: accessToken)
    }

    public func removeFromPlaylist(playlistItemID: String, accessToken: String) async throws {
        try await api.removeFromPlaylist(playlistItemID: playlistItemID, accessToken: accessToken)
    }
}
