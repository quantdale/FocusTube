import Foundation
import Observation
import FocusTubeCore

/// UI-facing search store. Submits only on explicit user action (never per
/// keystroke) and surfaces typed quota/error states. Pagination is explicit.
@MainActor
@Observable
public final class SearchStore {
    public private(set) var results: [VideoSummary] = []
    public private(set) var isLoading = false
    public private(set) var error: YouTubeAPIError?
    public private(set) var query: String = ""

    private var nextPageToken: String?
    private let auth: AuthSession
    private let api: YouTubeAPI
    private let service: SearchService

    public init(auth: AuthSession, api: YouTubeAPI) {
        self.auth = auth
        self.api = api
        self.service = SearchService(api: api)
    }

    /// Explicit submit. Never invoked on text changes.
    public func submit(_ query: String) async {
        self.query = query
        guard let token = await auth.accessToken() else {
            error = .unauthorized
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.search(query: query, accessToken: token)
            results = page.videos
            nextPageToken = page.nextPageToken
            error = nil
        } catch let err as YouTubeAPIError {
            error = err
        } catch {
            error = .unknown(status: -1)
        }
    }

    public func loadMore() async {
        guard let token = await auth.accessToken(), let page = nextPageToken else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await service.search(query: query, accessToken: token, pageToken: page)
            results.append(contentsOf: next.videos)
            nextPageToken = next.nextPageToken
        } catch let err as YouTubeAPIError {
            error = err
        } catch {
            error = .unknown(status: -1)
        }
    }
}
