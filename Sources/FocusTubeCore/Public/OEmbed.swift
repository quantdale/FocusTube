import Foundation

/// oEmbed metadata (ADR-0008). No duration, description or channel id.
public struct OEmbedMetadata: Equatable, Sendable, Codable {
    public let title: String
    public let authorName: String
    public let authorURL: URL?
    public let thumbnailURL: URL?
    public let width: Int?
    public let height: Int?

    enum CodingKeys: String, CodingKey {
        case title, width, height
        case authorName = "author_name"
        case authorURL = "author_url"
        case thumbnailURL = "thumbnail_url"
    }

    public init(title: String, authorName: String, authorURL: URL?, thumbnailURL: URL?, width: Int?, height: Int?) {
        self.title = title; self.authorName = authorName; self.authorURL = authorURL
        self.thumbnailURL = thumbnailURL; self.width = width; self.height = height
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        authorName = (try? c.decode(String.self, forKey: .authorName)) ?? ""
        authorURL = try? c.decode(URL.self, forKey: .authorURL)
        thumbnailURL = try? c.decode(URL.self, forKey: .thumbnailURL)
        width = try? c.decode(Int.self, forKey: .width)
        height = try? c.decode(Int.self, forKey: .height)
    }

    /// Portrait embeds are Shorts (ADR-0008 Shorts rule b).
    public var isPortrait: Bool {
        guard let width, let height, width > 0 else { return false }
        return height > width
    }
}

public struct OEmbedClient: Sendable {
    let http: HTTPFetching
    public init(http: HTTPFetching) { self.http = http }

    public func metadata(for id: YouTubeVideoID) async throws(PublicSourceError) -> OEmbedMetadata {
        let response: (data: Data, status: Int)
        do { response = try await http.get(PublicEndpoints.oEmbed(id)) } catch { throw .transport }
        if let err = PublicSourceError.from(status: response.status) { throw err }
        do { return try JSONDecoder().decode(OEmbedMetadata.self, from: response.data) } catch { throw .malformed }
    }
}
