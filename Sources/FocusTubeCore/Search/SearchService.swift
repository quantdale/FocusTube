import Foundation

/// A single page of hydrated, short-form-filtered search results.
public struct SearchResultPage: Sendable {
    public let videos: [VideoSummary]
    public let nextPageToken: String?
    public let query: String

    public init(videos: [VideoSummary], nextPageToken: String?, query: String) {
        self.videos = videos
        self.nextPageToken = nextPageToken
        self.query = query
    }
}

/// Quota-aware, explicit-submit search. Never performs a remote request except
/// when the caller explicitly submits a query. Results are hydrated (durations
/// known) and passed through `ShortFormPolicy` before any UI render.
public struct SearchService: Sendable {
    private let api: YouTubeAPI

    public init(api: YouTubeAPI) {
        self.api = api
    }

    public func search(query: String, accessToken: String, pageToken: String? = nil) async throws -> SearchResultPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResultPage(videos: [], nextPageToken: nil, query: trimmed) }

        let (ids, next) = try await api.searchVideoIDs(query: trimmed, accessToken: accessToken, pageToken: pageToken)
        // Zero hits: videos?id= with an empty id list is an HTTP 400 from the
        // Data API, so skip hydration and keep the pagination token.
        guard !ids.isEmpty else { return SearchResultPage(videos: [], nextPageToken: next, query: trimmed) }
        let details = try await api.fetchVideoDetails(ids: ids, accessToken: accessToken)

        let policy = ShortFormPolicy()
        let filtered = details.filter { item in
            guard let duration = item.durationSeconds else { return true }
            return !policy.isBlocked(durationSeconds: duration)
        }
        return SearchResultPage(videos: filtered, nextPageToken: next, query: trimmed)
    }
}
