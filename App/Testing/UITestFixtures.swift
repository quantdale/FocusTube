import Foundation
import FocusTubeCore

#if DEBUG
/// Deterministic launch-argument-driven fixture mode for UI tests.
///
/// Selected ONLY by the `-focustube-ui-test <scenario>` launch argument, which
/// ordinary users cannot set; this entire file is compiled out of Release
/// builds, so shipped binaries structurally cannot enter fake-service mode.
/// ADR-0008: fixtures serve canned public Atom feeds and oEmbed JSON.

// MARK: - Scenario selection

enum UITestScenario: String {
    /// No subscriptions yet.
    case empty = "empty"
    /// Subscribed to the fixture channel; feed loads.
    case homeLoaded = "home-loaded"
    /// Subscribed, but the feed request fails.
    case homeNetworkError = "home-network-error"
    case videoPage = "video-page"
    case librarySeeded = "library-seeded"
    /// No subscriptions; the Add tab can subscribe to the fixture channel.
    case addFlow = "add-flow"

    static func fromArguments(_ arguments: [String]) -> UITestScenario? {
        guard let index = arguments.firstIndex(of: "-focustube-ui-test"),
              arguments.indices.contains(index + 1) else { return nil }
        return UITestScenario(rawValue: arguments[index + 1])
    }

    var startsSubscribed: Bool { self == .homeLoaded || self == .homeNetworkError || self == .videoPage }
}

// MARK: - Deterministic content

enum FixtureContent {
    static let channelID = YouTubeChannelID("UCfixturefixturefixture0")!
    static let playlistID = YouTubePlaylistID("PLfixturefixture01")!
    /// Feed entries: three long-form videos (watch links) and one Short (/shorts/ link)
    /// that the ADR-0008 firewall must hide.
    static let entries: [(id: String, title: String, shorts: Bool, published: String)] = [
        ("fixHome0001", "Fixture Documentary One", false, "2026-10-15T12:00:00+00:00"),
        ("fixHome0002", "Fixture Interview Two", false, "2026-10-14T12:00:00+00:00"),
        ("fixShort001", "Fixture Sneaky Short", true, "2026-10-14T18:00:00+00:00"),
        ("fixHome0003", "Fixture Lecture Three", false, "2026-10-13T12:00:00+00:00"),
    ]

    static func feedXML(playlist: Bool = false) -> String {
        let items = entries.map { e in
            """
             <entry>
              <yt:videoId>\(e.id)</yt:videoId>
              <yt:channelId>\(channelID.rawValue)</yt:channelId>
              <title>\(e.title)</title>
              <link rel="alternate" href="https://www.youtube.com/\(e.shorts ? "shorts/" : "watch?v=")\(e.id)"/>
              <author><name>Fixture Channel</name></author>
              <published>\(e.published)</published>
              <media:group><media:description>Fixture description for \(e.title). Long-form content used by deterministic journeys.</media:description></media:group>
             </entry>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
         <yt:channelId>\(channelID.rawValue)</yt:channelId>
         \(playlist ? "<yt:playlistId>\(playlistID.rawValue)</yt:playlistId>" : "")
         <title>\(playlist ? "Fixture Playlist" : "Fixture Channel")</title>
         <author><name>Fixture Channel</name></author>
        \(items)
        </feed>
        """
    }

    static func oEmbedJSON(title: String, portrait: Bool) -> String {
        #"{"title":"\#(title)","author_name":"Fixture Channel","width":\#(portrait ? 113 : 200),"height":\#(portrait ? 200 : 113)}"#
    }
}

/// Canned responses for the keyless public endpoints.
struct FixtureHTTP: HTTPFetching {
    let feedFails: Bool

    func get(_ url: URL) async throws -> (data: Data, status: Int) {
        try await Task.sleep(nanoseconds: 50_000_000)
        let s = url.absoluteString
        if s == PublicEndpoints.channelFeed(FixtureContent.channelID).absoluteString {
            return feedFails ? (Data(), 500) : (Data(FixtureContent.feedXML().utf8), 200)
        }
        if s == PublicEndpoints.playlistFeed(FixtureContent.playlistID).absoluteString {
            return (Data(FixtureContent.feedXML(playlist: true).utf8), 200)
        }
        if s.hasPrefix("https://www.youtube.com/oembed") {
            if s.contains("fixPaste001") { return (Data(FixtureContent.oEmbedJSON(title: "Fixture Pasted Video", portrait: false).utf8), 200) }
            if s.contains("fixPortrait") { return (Data(FixtureContent.oEmbedJSON(title: "Portrait", portrait: true).utf8), 200) }
            return (Data(FixtureContent.oEmbedJSON(title: "Fixture Video", portrait: false).utf8), 200)
        }
        return (Data(), 404)
    }
}

enum FixtureLocalLibrary {
    /// Fresh per-launch library file, optionally pre-subscribed to the fixture channel.
    static func fileURL(for scenario: UITestScenario) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusTubeUITests-\(UUID().uuidString)")
            .appendingPathComponent("library.json")
        if scenario.startsSubscribed {
            var library = LocalLibrary()
            library.subscribe(FixtureContent.channelID, title: "Fixture Channel", now: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? encoder.encode(library).write(to: url)
        }
        return url
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
