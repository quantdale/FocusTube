import Foundation

/// Typed YouTube Data API v3 client over `HTTPPerforming`. Pure request
/// building and error mapping are separated so they are deterministically
/// testable without network or credentials. No tokens are ever logged.
public struct YouTubeDataClient: YouTubeAPI {
    private let performer: HTTPPerforming
    private let baseURL: URL

    public init(performer: HTTPPerforming = URLSession.shared, baseURL: URL = URL(string: "https://www.googleapis.com/youtube/v3")!) {
        self.performer = performer
        self.baseURL = baseURL
    }

    // MARK: - Endpoints

    public func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "subscriptions", accessToken: accessToken, query: [
            "part": "contentDetails",
            "mine": "true",
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(SubscriptionsResponse.self, from: data)
        return decoded.items.map { $0.contentDetails.relatedPlaylists.uploads }
    }

    public func fetchPlaylistVideoIDs(playlistID: String, accessToken: String) async throws -> [String] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "playlistItems", accessToken: accessToken, query: [
            "part": "contentDetails",
            "playlistId": playlistID,
            "maxResults": "50"
        ])
        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(PlaylistItemsResponse.self, from: data)
        return decoded.items.map { $0.contentDetails.videoId }
    }

    public func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        let request = try Self.buildRequest(baseURL: baseURL, path: "videos", accessToken: accessToken, query: [
            "part": "snippet,contentDetails",
            "id": ids.joined(separator: ",")
        ])
        let data = try await perform(request)
        let decoded = try JSONDecoder().decode(VideosResponse.self, from: data)
        return decoded.items.map { item in
            VideoSummary(
                id: item.id,
                title: item.snippet.title,
                channelTitle: item.snippet.channelTitle,
                durationSeconds: VideoSummary.duration(from: item.contentDetails.duration),
                publishedAt: ISO8601DateFormatter().date(from: item.snippet.publishedAt),
                thumbnailURL: item.snippet.thumbnails.medium?.url,
                description: item.snippet.description
            )
        }
    }

    // MARK: - Execution / mapping

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await performer.data(for: request)
        } catch {
            throw YouTubeAPIError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.unknown(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(http.statusCode)
        }
        return data
    }

    public static func mapError(_ statusCode: Int) -> YouTubeAPIError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .quotaExceeded
        case 404: return .notFound
        default: return .unknown(status: statusCode)
        }
    }

    private static func buildRequest(baseURL: URL, path: String, accessToken: String, query: [String: String]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw YouTubeAPIError.unknown(status: -1)
        }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw YouTubeAPIError.unknown(status: -1) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

// MARK: - Private decode models

private struct SubscriptionsResponse: Decodable {
    let items: [SubscriptionItem]
    struct SubscriptionItem: Decodable {
        let contentDetails: ContentDetails
        struct ContentDetails: Decodable {
            let relatedPlaylists: RelatedPlaylists
            struct RelatedPlaylists: Decodable {
                let uploads: String
            }
        }
    }
}

private struct PlaylistItemsResponse: Decodable {
    let items: [PlaylistItem]
    struct PlaylistItem: Decodable {
        let contentDetails: ContentDetails
        struct ContentDetails: Decodable {
            let videoId: String
        }
    }
}

private struct VideosResponse: Decodable {
    let items: [VideoItem]
    struct VideoItem: Decodable {
        let id: String
        let snippet: Snippet
        let contentDetails: ContentDetails
        struct Snippet: Decodable {
            let title: String
            let channelTitle: String
            let publishedAt: String
            let description: String
            let thumbnails: Thumbnails
            struct Thumbnails: Decodable {
                let medium: Thumbnail?
                struct Thumbnail: Decodable {
                    let url: URL
                }
            }
        }
        struct ContentDetails: Decodable {
            let duration: String
        }
    }
}
