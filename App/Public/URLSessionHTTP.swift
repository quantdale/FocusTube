import Foundation
import FocusTubeCore

/// Production `HTTPFetching` for the keyless public endpoints (ADR-0008).
/// Ephemeral session: no cookies, no persistent cache.
struct URLSessionHTTP: HTTPFetching {
    let session: URLSession

    init(session: URLSession = URLSessionHTTP.makeSession()) { self.session = session }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }

    func get(_ url: URL) async throws -> (data: Data, status: Int) {
        guard url.scheme == "https", url.host == "www.youtube.com" else { throw URLError(.unsupportedURL) }
        let (data, response) = try await session.data(from: url)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
