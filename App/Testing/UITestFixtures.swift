import Foundation
import AVFoundation
import CoreVideo
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

// MARK: - Extraction

struct FixtureExtractor: MediaExtracting {
    func resolve(videoID: String) async throws -> ResolvedMedia {
        FixtureContent.resolvedMedia(videoID: videoID)
    }
}

// MARK: - Playable fixture media (HB-014)

/// Generates a tiny but GENUINELY decodable H.264 MP4 so UI journeys can drive
/// the player to a real `.playing` state instead of asserting around a fake
/// "Playback failed" overlay. Generated at runtime inside the test harness —
/// no media binaries are committed, and this code is compiled out of Release.
enum FixtureMediaFactory {
    private static let lock = NSLock()
    /// Guarded by `lock`; `nonisolated(unsafe)` satisfies Swift 6 strict
    /// concurrency for this DEBUG-only test fixture.
    nonisolated(unsafe) private static var cachedMaster: URL?

    static func masterPlayableFile() throws -> URL {
        lock.lock()
        if let cachedMaster {
            lock.unlock()
            return cachedMaster
        }
        lock.unlock()

        // Generation runs OUTSIDE the lock: it is slow (encoder startup) and
        // a held lock would serialize every transfer's tempCopy behind it.
        let url: URL
        do {
            url = try generateMasterFile()
        } catch {
            // One cold-encoder retry: a transient first-use failure on a fresh
            // runner must not silently degrade EVERY transfer to filler bytes,
            // which downstream offline-playing journeys read as a product bug.
            url = try generateMasterFile()
        }

        lock.lock()
        // Last-writer-wins on the rare race; both products are valid media.
        cachedMaster = url
        lock.unlock()
        return url
    }

    private static func generateMasterFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("focustube-fixture-media-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = 64, height = 64, fps = 10, frames = 15
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ])
        input.expectsMediaDataInRealTime = false
        // H.264 encoders reliably accept 420v planar buffers; the earlier BGRA
        // configuration silently failed to encode on the CI runner (every
        // transfer degraded to the 4-byte filler fallback).
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "FixtureMedia", code: 1)
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frames {
            // BOUNDED readiness wait sized for a COLD headless software
            // encoder (first invocation on a fresh CI runner): a wedged
            // encoder must degrade to a thrown error (callers fall back),
            // never hang a thread forever.
            var waited = 0
            while !input.isReadyForMoreMediaData {
                waited += 1
                if waited > 7_500 { throw NSError(domain: "FixtureMedia", code: 5) }
                Thread.sleep(forTimeInterval: 0.002)
            }
            var pixelBuffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            }
            if pixelBuffer == nil {
                CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            }
            guard let buffer = pixelBuffer else {
                throw NSError(domain: "FixtureMedia", code: 2)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
                // Alternating dark/light luma gives visible playback motion;
                // neutral chroma (128) keeps the frame gray.
                let y: UInt8 = frame.isMultiple(of: 2) ? 40 : 200
                let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                let height0 = CVPixelBufferGetHeightOfPlane(buffer, 0)
                for row in 0..<height0 {
                    memset(base.advanced(by: row * stride), Int32(y), stride)
                }
            }
            if let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
                let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
                let height1 = CVPixelBufferGetHeightOfPlane(buffer, 1)
                for row in 0..<height1 {
                    memset(chroma.advanced(by: row * stride), 128, stride)
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? NSError(domain: "FixtureMedia", code: 3)
            }
        }
        input.markAsFinished()

        // BOUNDED completion wait — never an unbounded semaphore block.
        var waitedMs = 0
        while writer.status == .writing && waitedMs < 10_000 {
            Thread.sleep(forTimeInterval: 0.01)
            waitedMs += 10
        }
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "FixtureMedia", code: 4)
        }
        return url
    }

    /// A unique temp COPY per transfer: finalization MOVES temp files into
    /// place, so every completed event needs its own consumable path.
    static func tempCopy(for requestID: String, component: Int) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(requestID)#\(component).mp4")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: masterPlayableFile(), to: destination)
        return destination
    }
}

// MARK: - Scripted download transport

/// Deterministic admission: fixtures must never depend on host-disk free
/// space (a failed/low volume query refuses transfers conservatively with
/// zero bytes).
struct FixtureStorage: StorageProviding {
    func availableCapacity(for url: URL) -> Int64 { 512 * 1024 * 1024 * 1024 }
}

/// Drives the REAL coordinator/manager/service state machine with deterministic
/// byte events. `failsAfterProgress` switches the script to a transport failure.
/// Completed transfers finalize from a genuinely playable fixture MP4 (HB-014)
/// so offline playback reaches a real `.playing` state.
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
            // the completed event must point at real bytes — now real PLAYABLE
            // media, not opaque filler.
            do {
                let temp = try FixtureMediaFactory.tempCopy(for: request.id, component: component)
                onEvent(.completed(tempLocation: temp, component: component))
            } catch {
                // Generation failure degrades to the old filler-bytes behavior;
                // the transfer still completes (validation seam is off).
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("fixture-\(request.id)#\(component).bin")
                try? Data([0xFF, 0xFF, 0xFF, 0xFF]).write(to: temp)
                onEvent(.completed(tempLocation: temp, component: component))
            }
        }
    }

    func cancel(taskID: String) async {}
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
