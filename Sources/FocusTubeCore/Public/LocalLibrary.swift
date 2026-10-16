import Foundation

/// Local-first library (ADR-0008): no account, no sync. Pure value type with
/// policies; persisted by `LocalLibraryStore`.
public struct LocalSubscription: Hashable, Codable, Sendable, Identifiable {
    public let channelID: YouTubeChannelID
    public var title: String
    public let addedAt: Date
    public var id: String { channelID.rawValue }
    public init(channelID: YouTubeChannelID, title: String, addedAt: Date) {
        self.channelID = channelID; self.title = title; self.addedAt = addedAt
    }
}

public struct SavedPlaylist: Hashable, Codable, Sendable, Identifiable {
    public let playlistID: YouTubePlaylistID
    public var title: String
    public let addedAt: Date
    public var id: String { playlistID.rawValue }
    public init(playlistID: YouTubePlaylistID, title: String, addedAt: Date) {
        self.playlistID = playlistID; self.title = title; self.addedAt = addedAt
    }
}

public struct HistoryEntry: Equatable, Codable, Sendable, Identifiable {
    public var video: VideoSummary
    public var position: Double
    public var duration: Double?
    public var lastWatched: Date
    public var id: String { video.id }
}

public struct LocalLibrary: Equatable, Codable, Sendable {
    public static let historyLimit = 500
    public static let currentVersion = 1

    public var version = LocalLibrary.currentVersion
    public private(set) var subscriptions: [LocalSubscription] = []
    public private(set) var playlists: [SavedPlaylist] = []
    public private(set) var watchLater: [VideoSummary] = []
    public private(set) var history: [HistoryEntry] = []

    public init() {}

    // MARK: Subscriptions
    /// Returns false if already subscribed (title is refreshed).
    @discardableResult
    public mutating func subscribe(_ id: YouTubeChannelID, title: String, now: Date) -> Bool {
        if let i = subscriptions.firstIndex(where: { $0.channelID == id }) {
            if !title.isEmpty { subscriptions[i].title = title }
            return false
        }
        subscriptions.append(LocalSubscription(channelID: id, title: title, addedAt: now))
        subscriptions.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return true
    }
    public mutating func unsubscribe(_ id: YouTubeChannelID) { subscriptions.removeAll { $0.channelID == id } }
    public func isSubscribed(_ id: YouTubeChannelID) -> Bool { subscriptions.contains { $0.channelID == id } }

    // MARK: Playlists
    @discardableResult
    public mutating func savePlaylist(_ id: YouTubePlaylistID, title: String, now: Date) -> Bool {
        if let i = playlists.firstIndex(where: { $0.playlistID == id }) {
            if !title.isEmpty { playlists[i].title = title }
            return false
        }
        playlists.insert(SavedPlaylist(playlistID: id, title: title, addedAt: now), at: 0)
        return true
    }
    public mutating func removePlaylist(_ id: YouTubePlaylistID) { playlists.removeAll { $0.playlistID == id } }

    // MARK: Watch Later
    /// Newest first; Shorts (known ≤180 s) are refused. Returns false if refused or duplicate.
    @discardableResult
    public mutating func addToWatchLater(_ video: VideoSummary) -> Bool {
        if let d = video.durationSeconds, ShortFormPolicy().isBlocked(durationSeconds: d) { return false }
        guard !watchLater.contains(where: { $0.id == video.id }) else { return false }
        watchLater.insert(video, at: 0)
        return true
    }
    public mutating func removeFromWatchLater(_ id: String) { watchLater.removeAll { $0.id == id } }

    // MARK: History / resume
    public mutating func recordProgress(_ video: VideoSummary, position: Double, duration: Double?, now: Date) {
        guard position.isFinite, position >= 0 else { return }
        let entry = HistoryEntry(video: video, position: position,
                                 duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }, lastWatched: now)
        history.removeAll { $0.video.id == video.id }
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }
    public mutating func clearHistory() { history.removeAll() }

    /// Resume point: nil when barely started (<10 s) or nearly finished (≥95% / last 30 s).
    public func resumePosition(for videoID: String) -> Double? {
        guard let e = history.first(where: { $0.video.id == videoID }), e.position >= 10 else { return nil }
        if let d = e.duration, e.position >= d * 0.95 || d - e.position <= 30 { return nil }
        return e.position
    }

    // MARK: Local search (replaces YouTube search, ADR-0008)
    /// Case/diacritic-insensitive match on title or channel over known videos
    /// (`extra` = e.g. cached feed items). De-duplicated, Watch Later and history first.
    public func search(_ query: String, in extra: [VideoSummary] = []) -> [VideoSummary] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var seen = Set<String>(), out: [VideoSummary] = []
        for v in watchLater + history.map(\.video) + extra where !seen.contains(v.id) {
            let hay = (v.title + " " + v.channelTitle).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if terms.allSatisfy({ hay.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }) {
                seen.insert(v.id); out.append(v)
            }
        }
        return out
    }
}

/// Atomic JSON persistence for `LocalLibrary`. A corrupt file is moved aside
/// (`.corrupt`) and an empty library is returned, never a crash.
public actor LocalLibraryStore {
    public nonisolated let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public enum LoadOutcome: Equatable, Sendable { case loaded, empty, recoveredFromCorruption }

    public func load() -> (LocalLibrary, LoadOutcome) {
        guard let data = try? Data(contentsOf: fileURL) else { return (LocalLibrary(), .empty) }
        do {
            return (try Self.decoder.decode(LocalLibrary.self, from: data), .loaded)
        } catch {
            let aside = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return (LocalLibrary(), .recoveredFromCorruption)
        }
    }

    public func save(_ library: LocalLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(library).write(to: fileURL, options: .atomic)
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

extension YouTubeChannelID {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = YouTubeChannelID(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid channel id"))
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}

extension YouTubePlaylistID {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let v = YouTubePlaylistID(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "invalid playlist id"))
        }
        self = v
    }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
