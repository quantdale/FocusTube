import Foundation

/// A YouTube channel id (`UC` + 22 chars of `[A-Za-z0-9_-]`). ADR-0008.
public struct YouTubeChannelID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init?(_ raw: String) {
        guard raw.count == 24, raw.hasPrefix("UC"), YouTubeLink.isIDSafe(raw) else { return nil }
        rawValue = raw
    }
    public var description: String { rawValue }
    /// The channel's public uploads playlist id (`UU…`).
    public var uploadsPlaylistID: String { "UU" + rawValue.dropFirst(2) }
}

/// A YouTube playlist id (`PL…`, `UU…`, `OLAK5…`, etc.; 10–64 safe chars).
public struct YouTubePlaylistID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init?(_ raw: String) {
        guard (10...64).contains(raw.count), YouTubeLink.isIDSafe(raw) else { return nil }
        rawValue = raw
    }
    public var description: String { rawValue }
}

/// Result of parsing a pasted/shared link (ADR-0008).
public enum YouTubeLink: Equatable, Sendable {
    case video(YouTubeVideoID, playlist: YouTubePlaylistID?, startSeconds: Int?)
    case playlist(YouTubePlaylistID)
    case channel(YouTubeChannelID)

    public enum Rejection: Error, Equatable, Sendable {
        case empty
        case notAURL
        case notYouTube
        case insecureScheme
        /// Shorts are blocked by FocusTube's focus policy.
        case shorts
        /// `@handle`, `/c/` or `/user/`: not resolvable without the Data API or scraping.
        case unresolvableChannel(String)
        case unsupported

        public var userMessage: String {
            switch self {
            case .empty: return "Paste a YouTube link."
            case .notAURL, .unsupported: return "That doesn't look like a YouTube video, playlist or channel link."
            case .notYouTube: return "Only youtube.com and youtu.be links are supported."
            case .insecureScheme: return "Only https links are supported."
            case .shorts: return "Shorts aren't supported in FocusTube."
            case .unresolvableChannel:
                return "Channel handles can't be looked up without a Google account. On YouTube, open the channel, tap About › Share channel › Copy channel ID, and paste that (it starts with UC)."
            }
        }
    }

    static let hosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
        "youtu.be", "www.youtube-nocookie.com", "youtube-nocookie.com",
    ]

    static func isIDSafe(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { c in
            (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "-" || c == "_"
        }
    }

    public static func parse(_ input: String) throws(Rejection) -> YouTubeLink {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        // Documented convenience: a bare channel id.
        if let channel = YouTubeChannelID(text) { return .channel(channel) }
        var candidate = text
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let comps = URLComponents(string: candidate), let rawHost = comps.host?.lowercased() else {
            throw .notAURL
        }
        guard hosts.contains(rawHost) else { throw .notYouTube }
        guard comps.scheme?.lowercased() == "https" else { throw .insecureScheme }

        let segments = comps.path.split(separator: "/").map(String.init)
        let query = Dictionary(
            (comps.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let playlist = query["list"].flatMap(YouTubePlaylistID.init)
        let start = query["t"].flatMap(parseTime) ?? query["start"].flatMap(parseTime)

        if rawHost == "youtu.be" {
            guard let first = segments.first, let id = YouTubeVideoID(first) else { throw .unsupported }
            return .video(id, playlist: playlist, startSeconds: start)
        }
        guard let head = segments.first?.lowercased() else { throw .unsupported }
        switch head {
        case "shorts":
            throw .shorts
        case "watch":
            guard let v = query["v"], let id = YouTubeVideoID(v) else {
                if let playlist { return .playlist(playlist) }
                throw .unsupported
            }
            return .video(id, playlist: playlist, startSeconds: start)
        case "embed", "live", "v":
            guard segments.count >= 2, let id = YouTubeVideoID(segments[1]) else { throw .unsupported }
            return .video(id, playlist: playlist, startSeconds: start)
        case "playlist":
            guard let playlist else { throw .unsupported }
            return .playlist(playlist)
        case "channel":
            guard segments.count >= 2, let id = YouTubeChannelID(segments[1]) else { throw .unsupported }
            return .channel(id)
        case "c", "user":
            throw .unresolvableChannel(segments.count >= 2 ? segments[1] : "")
        default:
            if head.hasPrefix("@") { throw .unresolvableChannel(segments[0]) }
            throw .unsupported
        }
    }

    /// `90`, `90s`, `1m30s`, `1h2m3s`.
    static func parseTime(_ raw: String) -> Int? {
        if let n = Int(raw), n >= 0 { return n }
        var total = 0, current = 0, sawUnit = false
        for ch in raw.lowercased() {
            if let d = ch.wholeNumberValue { current = current * 10 + d; continue }
            switch ch {
            case "h": total += current * 3600
            case "m": total += current * 60
            case "s": total += current
            default: return nil
            }
            current = 0; sawUnit = true
        }
        return sawUnit && current == 0 ? total : nil
    }
}
