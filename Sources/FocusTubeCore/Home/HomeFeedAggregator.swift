import Foundation

/// Aggregates the authenticated subscription feed and applies the short-form
/// firewall (`ShortFormPolicy`) *before* any UI render. There is no Shorts
/// surface, route, or implicit autoplay path; load-more is an explicit caller
/// decision, never automatic infinite pagination.
public struct HomeFeedAggregator {
    private let api: YouTubeAPI

    public init(api: YouTubeAPI) {
        self.api = api
    }

    /// Fetches the subscription feed and removes short-form entries.
    public func fetchFeed(accessToken: String) async throws -> [VideoSummary] {
        let raw = try await api.fetchSubscriptionFeed(accessToken: accessToken)
        return filterShortForm(raw)
    }

    /// Pure short-form firewall. Entries at or below 180s (or otherwise blocked
    /// by `ShortFormPolicy`) are removed. Unknown duration is not assumed short.
    public func filterShortForm(_ items: [VideoSummary]) -> [VideoSummary] {
        let policy = ShortFormPolicy()
        return items.filter { item in
            guard let duration = item.durationSeconds else { return true }
            return !policy.isBlocked(durationSeconds: duration)
        }
    }
}
