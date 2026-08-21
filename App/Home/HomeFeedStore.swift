import Foundation
import Observation
import FocusTubeCore

/// UI-facing Home feed store. Owns fetch state and applies the `HomeFeedAggregator`
/// short-form firewall. Load-more is an explicit user action only.
@MainActor
@Observable
public final class HomeFeedStore {
    public private(set) var videos: [VideoSummary] = []
    public private(set) var nextPageToken: String?
    public private(set) var isLoading = false
    public private(set) var error: YouTubeAPIError?
    public private(set) var isAuthenticated = false

    private let auth: AuthSession
    private let api: YouTubeAPI
    private let aggregator: HomeFeedAggregator

    public init(auth: AuthSession, api: YouTubeAPI) {
        self.auth = auth
        self.api = api
        self.aggregator = HomeFeedAggregator(api: api)
    }

    public func restore() async {
        isAuthenticated = await auth.restore()
    }

    public func load() async {
        await fetch(pageToken: nil, replacing: true)
    }

    /// Explicit, user-triggered load-more. Appends the next page using the
    /// feed's continuation token; a no-op once the feed is exhausted.
    public func loadMore() async {
        guard let pageToken = nextPageToken, !pageToken.isEmpty else { return }
        await fetch(pageToken: pageToken, replacing: false)
    }

    private func fetch(pageToken: String?, replacing: Bool) async {
        guard let token = await auth.accessToken() else {
            isAuthenticated = false
            error = .unauthorized
            return
        }
        isAuthenticated = true
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await aggregator.fetchFeed(accessToken: token, pageToken: pageToken)
            if replacing {
                videos = page.videos
            } else {
                videos.append(contentsOf: page.videos)
            }
            nextPageToken = page.nextPageToken
            error = nil
        } catch let err as YouTubeAPIError {
            error = err
        } catch {
            self.error = .unknown(status: -1)
        }
    }
}
