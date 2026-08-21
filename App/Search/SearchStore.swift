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

    public private(set) var nextPageToken: String?
    private let auth: AuthSession
    private let api: YouTubeAPI
    private let service: SearchService
    /// Monotonic token for in-flight loads: a response may only mutate state
    /// while no newer submit/load-more has started (HB-004 stale-response race).
    private var loadGeneration = 0

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
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            // Only the newest load owns the spinner; a superseded response
            // must not clear it out from under the in-flight one.
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let page = try await service.search(query: query, accessToken: token)
            guard generation == loadGeneration else { return }
            results = page.videos
            nextPageToken = page.nextPageToken
            error = nil
        } catch let err as YouTubeAPIError {
            guard generation == loadGeneration else { return }
            error = err
        } catch {
            guard generation == loadGeneration else { return }
            self.error = .unknown(status: -1)
        }
    }

    public func loadMore() async {
        guard let token = await auth.accessToken(), let page = nextPageToken else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let next = try await service.search(query: query, accessToken: token, pageToken: page)
            guard generation == loadGeneration else { return }
            results.append(contentsOf: next.videos)
            nextPageToken = next.nextPageToken
        } catch let err as YouTubeAPIError {
            guard generation == loadGeneration else { return }
            error = err
        } catch {
            guard generation == loadGeneration else { return }
            self.error = .unknown(status: -1)
        }
    }
}
