import Foundation

/// Builds the local subscriptions feed from public Atom feeds (ADR-0008).
/// Bounded concurrency, per-feed refresh interval, Shorts firewall, de-dup,
/// newest first. No background polling: callers trigger `refresh`.
public actor PublicFeedAggregator {
    public struct Snapshot: Equatable, Sendable {
        public let videos: [VideoSummary]
        public let failures: [String: PublicSourceError]   // channel id → error
        public let hiddenShorts: Int
    }

    public static let defaultRefreshInterval: TimeInterval = 15 * 60

    private let client: PublicFeedClient
    private let refreshInterval: TimeInterval
    private let maxConcurrent: Int
    private var cache: [String: (fetchedAt: Date, entries: [FeedEntry])] = [:]
    /// Video ids known to be Shorts from other signals (portrait oEmbed, player duration ≤180 s).
    private var knownShorts: Set<String> = []
    /// Durations learned from the player (seconds).
    private var knownDurations: [String: Int] = [:]

    public init(client: PublicFeedClient, refreshInterval: TimeInterval = defaultRefreshInterval, maxConcurrent: Int = 4) {
        self.client = client
        self.refreshInterval = refreshInterval
        self.maxConcurrent = max(1, maxConcurrent)
    }

    public func markShort(_ videoID: String) { knownShorts.insert(videoID) }
    public func learnDuration(_ videoID: String, seconds: Int) {
        knownDurations[videoID] = seconds
        if ShortFormPolicy().isBlocked(durationSeconds: seconds) { knownShorts.insert(videoID) }
    }
    public func learn(_ metadata: OEmbedMetadata, for videoID: String) {
        if metadata.isPortrait { knownShorts.insert(videoID) }
    }

    /// Fetches stale feeds (or all, when `force`), then returns the merged snapshot.
    public func refresh(_ subscriptions: [LocalSubscription], now: Date, force: Bool = false, limit: Int = 200) async -> Snapshot {
        let ids = subscriptions.map(\.channelID)
        let stale = ids.filter { id in
            guard !force, let c = cache[id.rawValue] else { return true }
            return now.timeIntervalSince(c.fetchedAt) >= refreshInterval
        }
        var failures: [String: PublicSourceError] = [:]
        let client = self.client
        for chunkStart in stride(from: 0, to: stale.count, by: maxConcurrent) {
            let chunk = Array(stale[chunkStart..<min(chunkStart + maxConcurrent, stale.count)])
            let results = await withTaskGroup(of: (String, Result<[FeedEntry], PublicSourceError>).self) { group in
                for id in chunk {
                    group.addTask {
                        do { return (id.rawValue, .success(try await client.channel(id).entries)) }
                        catch let e as PublicSourceError { return (id.rawValue, .failure(e)) }
                        catch { return (id.rawValue, .failure(.transport)) }
                    }
                }
                var out: [(String, Result<[FeedEntry], PublicSourceError>)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (id, result) in results {
                switch result {
                case .success(let entries): cache[id] = (now, entries)
                case .failure(let e): failures[id] = e   // keep stale cache, if any
                }
            }
        }
        let wanted = Set(ids.map(\.rawValue))
        cache = cache.filter { wanted.contains($0.key) }
        return snapshot(failures: failures, limit: limit)
    }

    public func cachedSnapshot(limit: Int = 200) -> Snapshot { snapshot(failures: [:], limit: limit) }

    private func snapshot(failures: [String: PublicSourceError], limit: Int) -> Snapshot {
        var seen = Set<String>(), hidden = 0
        var merged: [FeedEntry] = []
        for entry in cache.values.flatMap(\.entries) where !seen.contains(entry.videoID) {
            seen.insert(entry.videoID)
            if Self.isShort(entry, knownShorts: knownShorts) { hidden += 1; continue }
            merged.append(entry)
        }
        merged.sort { ($0.published ?? .distantPast, $0.videoID) > ($1.published ?? .distantPast, $1.videoID) }
        let videos = merged.prefix(limit).map { e -> VideoSummary in
            let v = e.videoSummary
            guard let d = knownDurations[e.videoID] else { return v }
            return VideoSummary(id: v.id, title: v.title, channelTitle: v.channelTitle, durationSeconds: d,
                                publishedAt: v.publishedAt, thumbnailURL: v.thumbnailURL, description: v.description, channelID: v.channelID)
        }
        return Snapshot(videos: Array(videos), failures: failures, hiddenShorts: hidden)
    }

    /// ADR-0008 Shorts firewall: `/shorts/` link, or known from oEmbed/duration.
    public static func isShort(_ entry: FeedEntry, knownShorts: Set<String> = []) -> Bool {
        entry.isShortsLink || knownShorts.contains(entry.videoID)
    }
}
