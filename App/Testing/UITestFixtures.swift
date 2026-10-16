import Foundation
import FocusTubeCore

#if DEBUG
/// Deterministic launch-argument-driven fixture mode for UI tests.
///
/// Selected ONLY by the `-focustube-ui-test <scenario>` launch argument, which
/// ordinary users cannot set; this entire file is compiled out of Release
/// builds, so shipped binaries structurally cannot enter fake-service mode.
/// Production always uses the real implementations.

// MARK: - Scenario selection

enum UITestScenario: String {
    case signedOut = "signed-out"
    case homeLoaded = "home-loaded"
    case homeNetworkError = "home-network-error"
    case homeQuotaError = "home-quota-error"
    case searchReady = "search-ready"
    case searchEmpty = "search-empty"
    case searchError = "search-error"
    case videoPage = "video-page"
    case librarySeeded = "library-seeded"

    static func fromArguments(_ arguments: [String]) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: "-focustube-ui-test"),
              arguments.indices.contains(index + 1) else { return nil }
        return UITestScenario(rawValue: arguments[index + 1])
    }
}

// MARK: - Deterministic content

enum FixtureContent {
    static func video(
        _ id: String,
        _ title: String,
        seconds: Int?,
        channel: String = "Fixture Channel"
    ) -> VideoSummary {
        VideoSummary(
            id: id,
            title: title,
            channelTitle: channel,
            durationSeconds: seconds,
            publishedAt: nil,
            thumbnailURL: nil,
            description: "Fixture description for \(title). Long-form content used by deterministic journeys.",
            channelID: "UCfixture"
        )
    }

    /// Long-form Home fixtures (>= 10 minutes so they pass any firewall check).
    static let homeVideos: [VideoSummary] = [
        video("fix-home-1", "Fixture Documentary One", seconds: 1800),
        video("fix-home-2", "Fixture Interview Two", seconds: 2400),
        video("fix-home-3", "Fixture Lecture Three", seconds: 3600)
    ]

    static let homePageTwo: [VideoSummary] = [
        video("fix-home-4", "Fixture Essay Four", seconds: 1500),
        video("fix-home-5", "Fixture Panel Five", seconds: 2700)
    ]

    /// Search results include one 90-second short that ShortFormPolicy must
    /// filter before render — the UI journey asserts it never appears.
    static let searchDetails: [VideoSummary] = [
        video("fix-search-1", "Fixture Search Result Alpha", seconds: 1200),
        video("fix-search-short", "Fixture Sneaky Short", seconds: 90),
        video("fix-search-2", "Fixture Search Result Beta", seconds: 2000)
    ]

    static let searchPageTwo: [VideoSummary] = [
        video("fix-search-3", "Fixture Search Result Gamma", seconds: 900)
    ]

    /// Allowed ladder fully present so the picker shows all four options.
    static let comments: [Comment] = [
        Comment(id: "fc1", author: "Fixture Alice", text: "Fixture comment alpha", likeCount: 3, publishedAt: nil, replyCount: 1, replies: [
            Comment(id: "fc1r1", author: "Fixture Bob", text: "Fixture reply", likeCount: 1, publishedAt: nil, replyCount: 0)
        ]),
        Comment(id: "fc2", author: "Fixture Carol", text: "Fixture comment beta", likeCount: 7, publishedAt: nil, replyCount: 0)
    ]
}

// MARK: - Auth

/// Class (not struct) so sign-out can flip the in-memory session state and
/// sign-out journeys can observe the transition deterministically.
/// `@unchecked Sendable`: the single mutable flag is written only from the
/// main actor (UI actions) and read through async AuthSession methods in
/// tests; no cross-thread torn-state risk exists at fixture scale.
final class FixtureAuthSession: AuthSession, @unchecked Sendable {
    var authenticated: Bool

    init(authenticated: Bool) {
        self.authenticated = authenticated
    }

    var isAuthenticated: Bool { get async { authenticated } }
    func restore() async -> Bool { authenticated }
    func accessToken() async -> String? { authenticated ? "fixture-token" : nil }
    func signOut() async { authenticated = false }
}

// MARK: - API

/// Scenario-scripted YouTube Data API fake. No network I/O anywhere.
struct FixtureYouTubeAPI: YouTubeAPI {
    let feedError: YouTubeAPIError?
    let searchError: YouTubeAPIError?
    let searchHits: Bool

    init(feedError: YouTubeAPIError? = nil, searchError: YouTubeAPIError? = nil, searchHits: Bool = true) {
        self.feedError = feedError
        self.searchError = searchError
        self.searchHits = searchHits
    }

    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] {
        if let feedError { throw feedError }
        return ["fixture-uploads"]
    }

    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        ([], nil)
    }

    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        ids.compactMap { id in
            (FixtureContent.homeVideos + FixtureContent.homePageTwo + FixtureContent.searchDetails + FixtureContent.searchPageTwo)
                .first { $0.id == id }
        }
    }

    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        if let searchError { throw searchError }
        guard searchHits else { return ([], nil) }
        if pageToken == nil {
            return (["fix-search-1", "fix-search-short", "fix-search-2"], "fixture-search-token-2")
        } else {
            return (["fix-search-3"], nil)
        }
    }

    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage {
        CommentPage(comments: FixtureContent.comments, nextPageToken: nil, commentsDisabled: false)
    }

    // DDV2-04 mutation/lookup fakes: deterministic, no network, no tokens.

    func postTopLevelComment(videoID: String, text: String, accessToken: String) async throws -> Comment {
        Comment(id: "fc-posted", author: "Fixture You", text: text, likeCount: 0, publishedAt: Date(), replyCount: 0)
    }

    func postReply(parentCommentID: String, text: String, accessToken: String) async throws -> Comment {
        Comment(id: "fc-reply-posted", author: "Fixture You", text: text, likeCount: 0, publishedAt: Date(), replyCount: 0)
    }

    func findMySubscription(channelID: String, accessToken: String) async throws -> SubscriptionLookup? {
        SubscriptionLookup(subscriptionID: "SUB-fixture", channelTitle: "Fixture Channel")
    }

    func fetchMyVideoRating(videoID: String, accessToken: String) async throws -> VideoRatingState {
        .like
    }

    // DDV2-08 bounded-playlist fakes.

    func fetchMyPlaylists(accessToken: String) async throws -> [PlaylistSummary] {
        [PlaylistSummary(id: "PL-fixture", title: "Fixture Playlist", privacyStatus: "private", itemCount: 2)]
    }

    func fetchPlaylistItems(playlistID: String, accessToken: String) async throws -> [PlaylistItemSummary] {
        [PlaylistItemSummary(playlistItemID: "PI-1", videoID: "fix-home-1", title: "Fixture Documentary One", channelTitle: "Fixture Channel")]
    }

    func addToPlaylist(playlistID: String, videoID: String, accessToken: String) async throws {}

    func removeFromPlaylist(playlistItemID: String, accessToken: String) async throws {}

    func subscribe(channelID: String, accessToken: String) async throws {}

    func unsubscribe(subscriptionID: String, accessToken: String) async throws {}

    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws {}

    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        if let feedError { throw feedError }
        if pageToken == nil {
            return SubscriptionFeedPage(videos: FixtureContent.homeVideos, nextPageToken: "fixture-feed-token-2")
        }
        return SubscriptionFeedPage(videos: FixtureContent.homePageTwo, nextPageToken: nil)
    }
}

// MARK: - Library seeding

enum FixtureLibrarySeeder {
    /// Seeds history/saved rows once per store file so relaunch journeys can
    /// prove persistence without re-seeding duplicates.
    @MainActor
    static func seedIfNeeded(_ library: LibraryStore) {
        guard library.history.isEmpty, library.saved.isEmpty else { return }
        library.recordProgress(
            videoID: "fix-seeded-1",
            title: "Seeded In-Progress Video",
            channelTitle: "Fixture Channel",
            position: 300,
            duration: 1200,
            completed: false
        )
        library.save(videoID: "fix-seeded-2", title: "Seeded Saved Video", channelTitle: "Fixture Channel")
    }

    /// Dedicated persistent store so seeded state survives relaunches while
    /// staying isolated from the user's real Application Support library.
    static var containerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusTubeUITests")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("uitests.store")
    }
}
#endif

// MARK: - Fake player engine (ADR-0007)

#if DEBUG
/// Deterministic stand-in for the WKWebView IFrame engine in UI journeys.
/// Drives the real core `IFramePlayerController` with scripted bridge
/// messages (ready → buffering → playing) so the app's state handling is
/// exercised without network or WebKit.
@MainActor
final class FixturePlayerEngine: PlayerEngine {
    private var controller = IFramePlayerController()
    var onStateChange: (@MainActor (IFramePlayerState) -> Void)?
    var state: IFramePlayerState { controller.state }

    init() { _ = controller.apply(.ready) }

    /// UI fixtures use short ids like "fix-home-1"; map them to one valid id.
    static func resolveFixtureID(_ raw: String) -> YouTubeVideoID? {
        YouTubeVideoID(raw) ?? YouTubeVideoID("fixtureVid0")
    }

    func load(_ videoID: YouTubeVideoID, startSeconds: Double, autoplay: Bool) {
        apply(controller.handle(.load(videoID, startSeconds: startSeconds, autoplay: autoplay)))
        guard autoplay else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self, self.controller.state.videoID == videoID else { return }
            self.deliver(.stateChange(.buffering))
            self.deliver(.progress(currentTime: max(0, startSeconds), duration: 600))
            self.deliver(.stateChange(.playing))
        }
    }
    func play() { if !apply(controller.handle(.play)).isEmpty { deliver(.stateChange(.playing)) } }
    func pause() { if !apply(controller.handle(.pause)).isEmpty { deliver(.stateChange(.paused)) } }
    func seek(to seconds: Double) { apply(controller.handle(.seek(seconds))) }
    func setPlaybackRate(_ rate: Double) {
        if !apply(controller.handle(.setRate(rate))).isEmpty { deliver(.playbackRateChange(rate)) }
    }
    func stop() { apply(controller.handle(.stop)) }

    @discardableResult
    private func apply(_ commands: [IFramePlayerCommand]) -> [IFramePlayerCommand] {
        onStateChange?(controller.state)
        return commands
    }
    private func deliver(_ message: IFrameBridgeMessage) {
        _ = controller.apply(message)
        onStateChange?(controller.state)
    }
}
#endif
