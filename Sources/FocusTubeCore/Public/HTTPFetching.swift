import Foundation

/// Minimal GET abstraction so feed/oEmbed clients are Linux-testable (ADR-0008).
public protocol HTTPFetching: Sendable {
    func get(_ url: URL) async throws -> (data: Data, status: Int)
}

public enum PublicSourceError: Error, Equatable, Sendable {
    case notFound            // 404: unknown/removed channel, playlist or video
    case unauthorized        // 401/403: private or embedding disabled (oEmbed)
    case badRequest          // 400
    case server(Int)         // other non-2xx
    case transport           // network failure
    case malformed           // body could not be parsed

    static func from(status: Int) -> PublicSourceError? {
        switch status {
        case 200..<300: return nil
        case 404: return .notFound
        case 401, 403: return .unauthorized
        case 400: return .badRequest
        default: return .server(status)
        }
    }
}

/// Public, keyless endpoints used by FocusTube. Nothing else is contacted besides the IFrame embed.
public enum PublicEndpoints {
    public static func channelFeed(_ id: YouTubeChannelID) -> URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id.rawValue)")!
    }
    public static func playlistFeed(_ id: YouTubePlaylistID) -> URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(id.rawValue)")!
    }
    public static func oEmbed(_ id: YouTubeVideoID) -> URL {
        var c = URLComponents(string: "https://www.youtube.com/oembed")!
        c.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id.rawValue)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url!
    }
}
