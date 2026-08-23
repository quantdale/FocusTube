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
    case downloadFlow = "download-flow"
    case downloadFailure = "download-failure"

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
            description: nil
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
    static func resolvedMedia(videoID: String) -> ResolvedMedia {
        func stream(_ resolution: Int) -> MediaStream {
            MediaStream(
                id: "c\(resolution)-\(videoID)",
                videoID: videoID,
                resolution: resolution,
                kind: .combined,
                nativePlayable: true,
                container: "mp4",
                videoCodec: "avc1",
                audioCodec: "mp4a",
                // Never fetched by UI journeys; playback only needs an item.
                sourceURL: URL(string: "https://fixture.invalid/\(videoID)/\(resolution).mp4")!,
                expiresAt: nil
            )
        }
        return ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: [stream(1080), stream(720), stream(480), stream(360)],
            videoOnly: [],
            audioOnly: []
        )
    }

    static let comments: [Comment] = [
        Comment(id: "fc1", author: "Fixture Alice", text: "Fixture comment alpha", likeCount: 3, publishedAt: nil, replyCount: 1, replies: [
            Comment(id: "fc1r1", author: "Fixture Bob", text: "Fixture reply", likeCount: 1, publishedAt: nil, replyCount: 0)
        ]),
        Comment(id: "fc2", author: "Fixture Carol", text: "Fixture comment beta", likeCount: 7, publishedAt: nil, replyCount: 0)
    ]
}

// MARK: - Auth

struct FixtureAuthSession: AuthSession {
    let authenticated: Bool

    init(authenticated: Bool) {
        self.authenticated = authenticated
    }

    var isAuthenticated: Bool { get async { authenticated } }
    func restore() async -> Bool { authenticated }
    func accessToken() async -> String? { authenticated ? "fixture-token" : nil }
    func signOut() async {}
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

// MARK: - Extraction

struct FixtureExtractor: MediaExtracting {
    func resolve(videoID: String) async throws -> ResolvedMedia {
        FixtureContent.resolvedMedia(videoID: videoID)
    }
}

// MARK: - Scripted download transport

/// Drives the REAL coordinator/manager/service state machine with deterministic
/// byte events. `failsAfterProgress` switches the script to a transport failure.
final class ScriptedDownloadTransport: DownloadTransport, @unchecked Sendable {
    let failsAfterProgress: Bool

    init(failsAfterProgress: Bool = false) {
        self.failsAfterProgress = failsAfterProgress
    }

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        for component in request.components.indices {
            let total: Int64 = 1000
            for step in 1...4 {
                onEvent(.progress(component: component, bytes: Int64(step * 250), total: total))
            }
            if failsAfterProgress && component == 0 {
                onEvent(.failed(.transportFailed))
                return
            }
            // The coordinator finalizes by moving the temp file into place, so
            // the completed event must point at real bytes.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("fixture-\(request.id)#\(component).bin")
            try? Data([0xFF, 0xFF, 0xFF, 0xFF]).write(to: temp)
            onEvent(.completed(tempLocation: temp, component: component))
        }
    }

    func cancel(taskID: String) async {}
}

// MARK: - Library seeding

enum FixtureLibrarySeeder {
    /// Seeds history/saved rows once per store file so relaunch journeys can
    /// prove persistence without re-seeding duplicates.
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
