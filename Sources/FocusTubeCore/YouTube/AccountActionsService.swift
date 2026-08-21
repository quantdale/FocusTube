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
}
