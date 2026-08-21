import Foundation

/// One page of the Home feed: hydrated, short-form-filtered videos plus the
/// opaque continuation token for the next explicit load-more.
public struct HomeFeedPage: Sendable {
    public let videos: [VideoSummary]
    public let nextPageToken: String?

    public init(videos: [VideoSummary], nextPageToken: String?) {
        self.videos = videos
        self.nextPageToken = nextPageToken
    }
}

/// Aggregates the authenticated subscription feed and applies the short-form
/// firewall (`ShortFormPolicy`) *before* any UI render. There is no Shorts
/// surface, route, or implicit autoplay path; load-more is an explicit caller
/// decision, never automatic infinite pagination.
public struct HomeFeedAggregator: Sendable {
    private let api: YouTubeAPI

    public init(api: YouTubeAPI) {
        self.api = api
    }

    /// Fetches one page of the subscription feed and removes short-form entries.
    /// `pageToken` is the opaque continuation token from the previous page;
    /// omit it for the first page.
    public func fetchFeed(accessToken: String, pageToken: String? = nil) async throws -> HomeFeedPage {
        let page = try await api.fetchSubscriptionFeed(accessToken: accessToken, pageToken: pageToken)
        return HomeFeedPage(videos: filterShortForm(page.videos), nextPageToken: page.nextPageToken)
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
