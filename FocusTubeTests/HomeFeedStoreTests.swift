import XCTest
@testable import FocusTube
import FocusTubeCore

/// Deterministic park-and-release gate: in-flight API calls take a ticket on
/// arrival and suspend until the test releases that ticket, so response
/// delivery order is fully controlled (HB-011b stale-response coverage).
private actor CallGate {
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var preReleased: Set<Int> = []
    private var nextTicket = 0
    /// Calls that have taken a ticket (reached the API entry point).
    private(set) var arrivalCount = 0

    func takeTicket() -> Int {
        let ticket = nextTicket
        nextTicket += 1
        arrivalCount += 1
        return ticket
    }

    /// Parks the caller until `release(ticket:)` resumes it.
    func awaitRelease(ticket: Int) async {
        if preReleased.remove(ticket) != nil { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters[ticket] = continuation
        }
    }

    /// Resumes the parked call for `ticket`; if the call has not reached the
    /// park point yet, records the release so the later park returns at once.
    func release(ticket: Int) {
        if let waiter = waiters.removeValue(forKey: ticket) {
            waiter.resume()
        } else {
            preReleased.insert(ticket)
        }
    }
}

private struct ArrivalTimeout: Error {}

/// Hand-written deterministic `YouTubeAPI` fake for the subscription-feed
/// path. Outcomes are consumed in call arrival order from `scripted`, then
/// `fallback` applies forever. Successes are numbered in delivery order so
/// concurrent loads are distinguishable without timing.
private actor ScriptedFeedAPI: YouTubeAPI {
    enum Outcome {
        case success
        case failure(YouTubeAPIError)
    }

    private var scripted: [Outcome]
    private let fallback: Outcome
    private var deliveries = 0
    let gate: CallGate?

    init(scripted: [Outcome] = [], fallback: Outcome, gate: CallGate? = nil) {
        self.scripted = scripted
        self.fallback = fallback
        self.gate = gate
    }

    private func nextOutcome() -> Outcome {
        if !scripted.isEmpty { return scripted.removeFirst() }
        return fallback
    }

    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage {
        let outcome = nextOutcome()
        if let gate {
            let ticket = await gate.takeTicket()
            await gate.awaitRelease(ticket: ticket)
        }
        switch outcome {
        case .failure(let error):
            throw error
        case .success:
            // Numbered in delivery order; the stale-response test relies on
            // the newest load delivering first.
            let index = deliveries
            deliveries += 1
            return SubscriptionFeedPage(
                videos: [VideoSummary(id: "page-\(index)", title: "Page \(index)", channelTitle: "channel", durationSeconds: 600, publishedAt: nil, thumbnailURL: nil, description: nil)],
                nextPageToken: nil
            )
        }
    }

    // Paths HomeFeedStore never exercises.
    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { fatalError("unexpected call") }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { fatalError("unexpected call") }
    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] { fatalError("unexpected call") }
    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { fatalError("unexpected call") }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { fatalError("unexpected call") }
    func subscribe(channelID: String, accessToken: String) async throws { fatalError("unexpected call") }
    func unsubscribe(subscriptionID: String, accessToken: String) async throws { fatalError("unexpected call") }
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws { fatalError("unexpected call") }
}

@MainActor
final class HomeFeedStoreTests: XCTestCase {
    /// Polls until at least `minimum` API calls have reached the gate, with a
    /// hard deadline so a regression fails the test instead of hanging CI.
    private func waitForArrivals(_ minimum: Int, on gate: CallGate) async throws {
        for _ in 0..<2000 {
            if await gate.arrivalCount >= minimum { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("timed out waiting for \(minimum) gated API call(s)")
        throw ArrivalTimeout()
    }

    func testNetworkFailureDuringLoadSurfacesTypedErrorAndSettlesLoading() async {
        let store = HomeFeedStore(auth: FakeAuthSession(), api: ScriptedFeedAPI(fallback: .failure(.network)))

        await store.load()

        XCTAssertEqual(store.error, .network)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.videos.isEmpty)
        // Token retrieval succeeded before the transport failure, so the store
        // still considers the session authenticated (intentional behavior).
        XCTAssertTrue(store.isAuthenticated)
    }

    func testUnauthorizedLoadSurfacesTypedErrorAndKeepsLoadedVideos() async {
        // First load succeeds; the second hits a 401-class transport error.
        let api = ScriptedFeedAPI(scripted: [.success, .failure(.unauthorized)], fallback: .success)
        let store = HomeFeedStore(auth: FakeAuthSession(), api: api)

        await store.load()
        XCTAssertEqual(store.videos.map(\.id), ["page-0"])
        XCTAssertNil(store.error)

        await store.load()
        XCTAssertEqual(store.error, .unauthorized)
        // Intentional current behavior: an auth-class failure surfaces the
        // typed error but does not wipe already-rendered content.
        XCTAssertEqual(store.videos.map(\.id), ["page-0"])
        XCTAssertFalse(store.isLoading)
    }

    func testStaleFeedResponseDoesNotRegressNewerResults() async throws {
        let gate = CallGate()
        let store = HomeFeedStore(auth: FakeAuthSession(), api: ScriptedFeedAPI(fallback: .success, gate: gate))

        // Load A parks in flight before load B starts; tickets follow arrival
        // order, so A holds ticket 0 and B holds ticket 1.
        let taskA = Task { await store.load() }
        try await waitForArrivals(1, on: gate)
        let taskB = Task { await store.load() }
        try await waitForArrivals(2, on: gate)

        // Deliver B's response while A is still parked; delivery order makes
        // B's page "page-0".
        await gate.release(ticket: 1)
        await taskB.value

        XCTAssertEqual(store.videos.map(\.id), ["page-0"])
        XCTAssertNil(store.error)
        // The newest fetch owns the spinner: B's completion clears it even
        // though A is still parked.
        XCTAssertFalse(store.isLoading)

        // A's late response must not regress any visible state.
        await gate.release(ticket: 0)
        await taskA.value

        XCTAssertEqual(store.videos.map(\.id), ["page-0"])
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }
}
