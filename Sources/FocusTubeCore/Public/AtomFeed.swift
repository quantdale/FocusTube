import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One video entry from a public YouTube Atom feed.
public struct FeedEntry: Equatable, Sendable, Codable {
    public let videoID: String
    public let title: String
    public let channelID: String?
    public let channelTitle: String
    public let published: Date?
    public let updated: Date?
    public let link: URL?
    public let thumbnailURL: URL?
    public let summary: String?

    /// YouTube links Shorts in feeds as `/shorts/<id>` (ADR-0008 Shorts rule a).
    public var isShortsLink: Bool { link.map { ShortFormPolicy().isBlocked(urlPath: $0.path + "/") } ?? false }

    public var videoSummary: VideoSummary {
        VideoSummary(id: videoID, title: title, channelTitle: channelTitle, durationSeconds: nil,
                     publishedAt: published, thumbnailURL: thumbnailURL, description: summary, channelID: channelID)
    }
}

public struct AtomFeed: Equatable, Sendable {
    public let title: String
    public let channelID: String?
    public let playlistID: String?
    public let authorName: String?
    public let entries: [FeedEntry]
    /// Entries skipped because required fields (video id) were missing/invalid.
    public let skippedEntries: Int
}

/// Tolerant parser for `youtube.com/feeds/videos.xml` (channel or playlist).
/// Unknown elements are ignored; entries without a valid video id are skipped.
public enum AtomFeedParser {
    public static func parse(_ data: Data) throws(PublicSourceError) -> AtomFeed {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse(), delegate.sawFeed else { throw .malformed }
        return AtomFeed(title: delegate.feedTitle, channelID: delegate.feedChannelID, playlistID: delegate.feedPlaylistID,
                        authorName: delegate.feedAuthor, entries: delegate.entries, skippedEntries: delegate.skipped)
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sawFeed = false
        var feedTitle = "", feedChannelID: String?, feedPlaylistID: String?, feedAuthor: String?
        var entries: [FeedEntry] = []
        var skipped = 0

        private var stack: [String] = []
        private var text = ""
        private var entry: [String: String]?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            stack.append(name)
            text = ""
            switch name {
                        case "entry": entry = [:]
            case "link" where entry != nil:
                if attributes["rel"] == "alternate" || attributes["rel"] == nil { entry?["link"] = attributes["href"] }
            case "media:thumbnail" where entry != nil:
                entry?["thumb"] = attributes["url"]
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
            if entry != nil {
                switch (name, parent) {
                case ("yt:videoId", _): entry?["videoId"] = value
                case ("yt:channelId", _): entry?["channelId"] = value
                case ("title", "entry"): entry?["title"] = value
                case ("name", "author"): entry?["author"] = value
                case ("published", "entry"): entry?["published"] = value
                case ("updated", "entry"): entry?["updated"] = value
                case ("media:description", _): entry?["summary"] = value
                case ("entry", _): finishEntry()
                default: break
                }
            } else {
                switch (name, parent) {
                case ("feed", _) where stack.count == 1: sawFeed = true
                case ("title", "feed"): feedTitle = value
                case ("yt:channelId", "feed"): feedChannelID = value.isEmpty ? nil : value
                case ("yt:playlistId", "feed"): feedPlaylistID = value.isEmpty ? nil : value
                case ("name", "author") where stack.count == 3: feedAuthor = value
                default: break
                }
            }
            stack.removeLast()
            text = ""
        }

        private func finishEntry() {
            defer { entry = nil }
            guard let e = entry, let id = e["videoId"], YouTubeVideoID(id) != nil else { skipped += 1; return }
            var channelID = e["channelId"]
            if let c = channelID, YouTubeChannelID(c) == nil { channelID = nil }
            entries.append(FeedEntry(
                videoID: id,
                title: e["title"] ?? "",
                channelID: channelID,
                channelTitle: e["author"] ?? feedAuthor ?? "",
                published: AtomFeedParser.date(e["published"]),
                updated: AtomFeedParser.date(e["updated"]),
                link: e["link"].flatMap(URL.init(string:)),
                thumbnailURL: e["thumb"].flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil },
                summary: e["summary"].flatMap { $0.isEmpty ? nil : $0 }
            ))
        }
    }
}

/// Fetches and parses public feeds.
public struct PublicFeedClient: Sendable {
    let http: HTTPFetching
    public init(http: HTTPFetching) { self.http = http }

    public func channel(_ id: YouTubeChannelID) async throws(PublicSourceError) -> AtomFeed {
        try await fetch(PublicEndpoints.channelFeed(id))
    }
    public func playlist(_ id: YouTubePlaylistID) async throws(PublicSourceError) -> AtomFeed {
        try await fetch(PublicEndpoints.playlistFeed(id))
    }
    private func fetch(_ url: URL) async throws(PublicSourceError) -> AtomFeed {
        let response: (data: Data, status: Int)
        do { response = try await http.get(url) } catch { throw .transport }
        if let err = PublicSourceError.from(status: response.status) { throw err }
        return try AtomFeedParser.parse(response.data)
    }
}
