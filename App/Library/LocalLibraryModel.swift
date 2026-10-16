import Foundation
import Observation
import os
import FocusTubeCore

/// App-side owner of the local-first library (ADR-0008): subscriptions and
/// saved playlists (core `LocalLibrary`, JSON on disk) plus the public
/// subscriptions feed. Watch history and Watch Later stay in the SwiftData
/// `LibraryStore`.
@MainActor
@Observable
final class LocalLibraryModel {
    private(set) var library = LocalLibrary()
    private(set) var feed: [VideoSummary] = []
    private(set) var feedFailures: [String: PublicSourceError] = [:]
    private(set) var hiddenShorts = 0
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var persistenceDegraded = false

    @ObservationIgnored private let store: LocalLibraryStore
    @ObservationIgnored let aggregator: PublicFeedAggregator
    @ObservationIgnored let feedClient: PublicFeedClient
    @ObservationIgnored let oEmbed: OEmbedClient
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var oEmbedCache: [String: OEmbedMetadata] = [:]

    init(http: HTTPFetching, fileURL: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        store = LocalLibraryStore(fileURL: fileURL)
        feedClient = PublicFeedClient(http: http)
        oEmbed = OEmbedClient(http: http)
        aggregator = PublicFeedAggregator(client: feedClient)
        self.now = now
    }

    static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusTube", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    func load() async {
        let (loaded, outcome) = await store.load()
        library = loaded
        if outcome == .recoveredFromCorruption {
            Self.logger.fault("library.json was corrupt; moved aside and started empty")
        }
    }

    // MARK: Subscriptions

    func isSubscribed(_ id: YouTubeChannelID) -> Bool { library.isSubscribed(id) }

    /// Subscribes after validating the channel through its public feed (title comes from the feed).
    func subscribe(_ id: YouTubeChannelID) async throws(PublicSourceError) -> String {
        let feed = try await feedClient.channel(id)
        let title = feed.title.isEmpty ? (feed.authorName ?? id.rawValue) : feed.title
        library.subscribe(id, title: title, now: now())
        await persist()
        await refresh(force: true)
        return title
    }

    /// Local subscribe when the title is already known (e.g. from a video page).
    func subscribe(_ id: YouTubeChannelID, title: String) async {
        library.subscribe(id, title: title, now: now())
        await persist()
    }

    func unsubscribe(_ id: YouTubeChannelID) async {
        library.unsubscribe(id)
        await persist()
        await refresh()
    }

    // MARK: Playlists

    func savePlaylist(_ id: YouTubePlaylistID) async throws(PublicSourceError) -> AtomFeed {
        let feed = try await feedClient.playlist(id)
        library.savePlaylist(id, title: feed.title.isEmpty ? id.rawValue : feed.title, now: now())
        await persist()
        return feed
    }

    func removePlaylist(_ id: YouTubePlaylistID) async {
        library.removePlaylist(id)
        await persist()
    }

    func playlistVideos(_ id: YouTubePlaylistID) async throws(PublicSourceError) -> [VideoSummary] {
        try await feedClient.playlist(id).entries.filter { !$0.isShortsLink }.map(\.videoSummary)
    }

    // MARK: Feed

    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let snap = await aggregator.refresh(library.subscriptions, now: now(), force: force)
        feed = snap.videos
        feedFailures = snap.failures
        hiddenShorts = snap.hiddenShorts
        lastRefresh = now()
    }

    /// ADR-0008 Shorts rule d: durations learned from the player feed back into the firewall.
    func learnDuration(videoID: String, seconds: Double) async {
        guard seconds.isFinite, seconds > 0 else { return }
        await aggregator.learnDuration(videoID, seconds: Int(seconds.rounded()))
        feed = await aggregator.cachedSnapshot().videos
    }

    // MARK: Metadata

    func metadata(for id: YouTubeVideoID) async -> OEmbedMetadata? {
        if let cached = oEmbedCache[id.rawValue] { return cached }
        guard let m = try? await oEmbed.metadata(for: id) else { return nil }
        oEmbedCache[id.rawValue] = m
        await aggregator.learn(m, for: id.rawValue)
        return m
    }

    /// Builds a summary for a pasted video link from oEmbed (or a minimal fallback).
    func summary(for id: YouTubeVideoID) async -> (VideoSummary, isShort: Bool) {
        if let known = feed.first(where: { $0.id == id.rawValue }) { return (known, false) }
        let m = await metadata(for: id)
        let summary = VideoSummary(
            id: id.rawValue,
            title: m?.title ?? "YouTube video",
            channelTitle: m?.authorName ?? "",
            durationSeconds: nil,
            publishedAt: nil,
            thumbnailURL: m?.thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(id.rawValue)/hqdefault.jpg"),
            description: nil
        )
        return (summary, m?.isPortrait ?? false)
    }

    func localSearch(_ query: String, extra: [VideoSummary] = []) -> [VideoSummary] {
        library.search(query, in: feed + extra)
    }

    private func persist() async {
        do {
            try await store.save(library)
            persistenceDegraded = false
        } catch {
            persistenceDegraded = true
            Self.logger.error("library.json save failed: \(error.localizedDescription)")
        }
    }

    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "local-library")
}
