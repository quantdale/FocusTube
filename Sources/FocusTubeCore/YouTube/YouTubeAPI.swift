import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Typed YouTube Data API error classes required by G3 acceptance.
public enum YouTubeAPIError: Error, Equatable, Sendable {
    case unauthorized
    case quotaExceeded
    /// Permanent permission denial (e.g. legacy reason "forbidden"/
    /// "insufficientPermissions" or canonical status PERMISSION_DENIED).
    /// Retrying cannot succeed; UI must not offer retry guidance.
    case forbidden
    case commentsDisabled
    case notFound
    case network
    case decode
    /// Caller-supplied input failed validation (e.g. empty comment text).
    /// Never surfaced from transport/decoding paths.
    case invalidInput
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

/// Read-only boundary over the YouTube Data API v3. Media extraction
/// (YouTubeKit) is never coupled to this; the API client only needs an OAuth
/// access token (or API key) and returns normalized `VideoSummary` values.
///
/// HB-019: read and mutation surfaces are separate protocols with NO
/// protocol-extension throwing defaults, so a conformer can no longer compile
/// while silently inheriting `unknown(status:-1)` failures for endpoints it
/// forgot to implement. The only extension-provided member is
/// `fetchSubscriptionFeed`, whose default is REAL composed behavior over the
/// required read methods — not a trap.
public protocol YouTubeReading: Sendable {
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
    /// One page of the subscription feed as hydrated video summaries, with an
    /// opaque continuation token for explicit load-more. A REAL composed
    /// default is provided by extension below (it chains the required read
    /// methods); conformers may override it — dynamic dispatch applies because
    /// it is a requirement, unlike the removed HB-019 throwing stubs.
    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage
}

/// Mutation and authenticated-lookup boundary. Every conformer implements each
/// endpoint explicitly; there are no defaults to inherit silently.
public protocol YouTubeWriting: Sendable {
    /// Subscribe the authenticated user to a channel.
    func subscribe(channelID: String, accessToken: String) async throws
    /// Unsubscribe by subscription resource ID.
    func unsubscribe(subscriptionID: String, accessToken: String) async throws
    /// Set the authenticated user's rating for a video.
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws
    /// Creates a top-level comment on a video (commentThreads.insert).
    func postTopLevelComment(videoID: String, text: String, accessToken: String) async throws -> Comment
    /// Creates a reply under an existing comment (comments.insert).
    /// `parentCommentID` is the parent comment's resource id.
    func postReply(parentCommentID: String, text: String, accessToken: String) async throws -> Comment
    /// Looks up the authenticated user's subscription to one channel and returns
    /// the subscription RESOURCE ID required for unsubscribe; nil when absent.
    func findMySubscription(channelID: String, accessToken: String) async throws -> SubscriptionLookup?
    /// The authenticated user's current rating state for a video (getRating).
    func fetchMyVideoRating(videoID: String, accessToken: String) async throws -> VideoRatingState
    /// The authenticated user's playlists (bounded first page, 50).
    func fetchMyPlaylists(accessToken: String) async throws -> [PlaylistSummary]
    /// Items of one playlist with their removable resource ids (first page).
    func fetchPlaylistItems(playlistID: String, accessToken: String) async throws -> [PlaylistItemSummary]
    /// Appends a video to one of the user's playlists.
    func addToPlaylist(playlistID: String, videoID: String, accessToken: String) async throws
    /// Removes an item by its playlistItem resource id.
    func removeFromPlaylist(playlistItemID: String, accessToken: String) async throws
}

/// Full API boundary: everything a production client implements. Read-path
/// stores/services take the narrower `YouTubeReading`; mutation-capable fakes
/// and views compose both via this typealias.
public typealias YouTubeAPI = YouTubeReading & YouTubeWriting

/// Result of looking up the user's subscription to a channel. Carries the
/// resource id required by `subscriptions.delete` — an unsubscribe can never be
/// issued against a bare channel id.
public struct SubscriptionLookup: Sendable, Hashable {
    public let subscriptionID: String
    public let channelTitle: String?

    public init(subscriptionID: String, channelTitle: String?) {
        self.subscriptionID = subscriptionID
        self.channelTitle = channelTitle
    }
}

/// The authenticated user's rating state for a video, as reported by
/// `videos.getRating` (superset of the writable `VideoRating` actions).
public enum VideoRatingState: String, Sendable {
    case like
    case dislike
    case none
    case unspecified
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

/// Tuning constants for subscription-feed detail hydration.
private enum FeedHydrationPolicy {
    /// `videos.list` rejects larger id= lists with HTTP 400.
    static let batchSize = 50
    /// Sliding-window width for concurrent detail hydration. Bounded so a
    /// very large first load cannot burst dozens of simultaneous requests;
    /// four keeps several round trips overlapped without aggressive fan-out.
    static let maxConcurrentBatches = 4
}

/// Fetches detail batches through a sliding-window task group so at most
/// `FeedHydrationPolicy.maxConcurrentBatches` requests are ever in flight.
/// Results come back indexed by their batch position, so concatenation order
/// equals input order regardless of completion order. A failing batch fails
/// the whole page (and cancels siblings), matching the previous sequential
/// error contract.
fileprivate func fetchDetailBatchesConcurrently<T: YouTubeReading>(
    _ batches: [[String]],
    accessToken: String,
    api: T
) async throws -> [[VideoSummary]] {
    guard batches.count > 1 else {
        var only: [[VideoSummary]] = []
        for batch in batches {
            only.append(try await api.fetchVideoDetails(ids: batch, accessToken: accessToken))
        }
        return only
    }
    var results = [[VideoSummary]?](repeating: nil, count: batches.count)
    try await withThrowingTaskGroup(
        of: (index: Int, videos: [VideoSummary]).self
    ) { group in
        var nextToDispatch = 0
        let initialWindow = min(FeedHydrationPolicy.maxConcurrentBatches, batches.count)
        while nextToDispatch < initialWindow {
            let index = nextToDispatch
            nextToDispatch += 1
            let batch = batches[index]
            group.addTask {
                (index, try await api.fetchVideoDetails(ids: batch, accessToken: accessToken))
            }
        }
        for try await (index, videos) in group {
            results[index] = videos
            if nextToDispatch < batches.count {
                let dispatchedIndex = nextToDispatch
                nextToDispatch += 1
                let batch = batches[dispatchedIndex]
                group.addTask {
                    (dispatchedIndex, try await api.fetchVideoDetails(ids: batch, accessToken: accessToken))
                }
            }
        }
    }
    return results.compactMap { $0 }
}

extension YouTubeReading {
    /// Convenience overload fetching the first feed page.
    public func fetchSubscriptionFeed(accessToken: String) async throws -> SubscriptionFeedPage {
        try await fetchSubscriptionFeed(accessToken: accessToken, pageToken: nil)
    }

    /// Default implementation of the required feed aggregation: playlists are
    /// walked in subscription order; each visits at most
    /// two `playlistItems` pages per call to bound quota. The walk pauses at
    /// the first playlist that still has more pages when the cap is hit, and
    /// its position ("<playlistIndex>|<pageToken>") becomes the page's opaque
    /// continuation token; unrecognized or stale tokens restart from the first
    /// playlist. Detail hydration chunks ids into batches of 50 because
    /// `videos.list` rejects larger id= lists with HTTP 400.
    ///
    /// Hydration batches run with bounded concurrency: every batch would be
    /// fetched regardless, so total quota cost is unchanged — only wall-clock
    /// latency collapses from one round trip per batch toward roughly one
    /// round trip overall. Output order remains exactly input order no matter
    /// which batch completes first (results are placed by batch index).
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
        summaries.reserveCapacity(ids.count)
        let batches = stride(from: 0, to: ids.count, by: FeedHydrationPolicy.batchSize).map { batchStart in
            Array(ids[batchStart..<min(batchStart + FeedHydrationPolicy.batchSize, ids.count)])
        }
        let batchResults = try await fetchDetailBatchesConcurrently(batches, accessToken: accessToken, api: self)
        for batchVideos in batchResults {
            summaries.append(contentsOf: batchVideos)
        }
        return SubscriptionFeedPage(videos: summaries, nextPageToken: continuation)
    }
}
