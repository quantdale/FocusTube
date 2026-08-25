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

/// Hand-written deterministic `YouTubeAPI` fake. Outcomes are consumed in call
/// arrival order from `scripted`, then `fallback` applies forever. Success
/// echoes the submitted query as one long-form result id so concurrent loads
/// are distinguishable without timing.
    private actor ScriptedSearchAPI: YouTubeReading {
    enum Outcome {
        case success
        case failure(YouTubeAPIError)
    }

    private var scripted: [Outcome]
    private let fallback: Outcome
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

    func searchVideoIDs(query: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) {
        let outcome = nextOutcome()
        if let gate {
            let ticket = await gate.takeTicket()
            await gate.awaitRelease(ticket: ticket)
        }
        switch outcome {
        case .success:
            return (ids: [query], nextPageToken: nil)
        case .failure(let error):
            throw error
        }
    }

    func fetchVideoDetails(ids: [String], accessToken: String) async throws -> [VideoSummary] {
        ids.map { id in
            // Long-form duration (600s) passes the ShortFormPolicy firewall.
            VideoSummary(id: id, title: "details-\(id)", channelTitle: "channel", durationSeconds: 600, publishedAt: nil, thumbnailURL: nil, description: nil)
        }
    }

    // Paths SearchStore never exercises.
    func fetchSubscriptionUploadsPlaylistIDs(accessToken: String) async throws -> [String] { fatalError("unexpected call") }
    func fetchPlaylistVideoIDs(playlistID: String, accessToken: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { fatalError("unexpected call") }
    func fetchSubscriptionFeed(accessToken: String, pageToken: String?) async throws -> SubscriptionFeedPage { fatalError("unexpected call") }
    func fetchComments(videoID: String, accessToken: String, pageToken: String?) async throws -> CommentPage { fatalError("unexpected call") }
    func subscribe(channelID: String, accessToken: String) async throws { fatalError("unexpected call") }
    func unsubscribe(subscriptionID: String, accessToken: String) async throws { fatalError("unexpected call") }
    func rateVideo(videoID: String, rating: VideoRating, accessToken: String) async throws { fatalError("unexpected call") }
}

@MainActor
final class SearchStoreTests: XCTestCase {
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

    func testNetworkFailureSurfacesTypedErrorAndSettlesLoading() async {
        let store = SearchStore(auth: FakeAuthSession(), api: ScriptedSearchAPI(fallback: .failure(.network)))

        await store.submit("network-failure")

        XCTAssertEqual(store.error, .network)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.results.isEmpty)
    }

    func testQuotaExceededSurfacesTypedQuotaError() async {
        let store = SearchStore(auth: FakeAuthSession(), api: ScriptedSearchAPI(fallback: .failure(.quotaExceeded)))

        await store.submit("quota")

        XCTAssertEqual(store.error, .quotaExceeded)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.results.isEmpty)
    }

    func testUnauthorizedFailureSurfacesTypedErrorAndKeepsPreviousResults() async {
        // First submit succeeds; the second hits a 401-class transport error.
        let api = ScriptedSearchAPI(scripted: [.success, .failure(.unauthorized)], fallback: .success)
        let store = SearchStore(auth: FakeAuthSession(), api: api)

        await store.submit("first")
        XCTAssertEqual(store.results.map(\.id), ["first"])
        XCTAssertNil(store.error)

        await store.submit("second")
        XCTAssertEqual(store.error, .unauthorized)
        // Intentional current behavior: an auth-class failure surfaces the
        // typed error but does not wipe already-rendered results.
        XCTAssertEqual(store.results.map(\.id), ["first"])
        XCTAssertFalse(store.isLoading)
    }

    func testStaleSearchResponseDoesNotRegressNewerResults() async throws {
        let gate = CallGate()
        let store = SearchStore(auth: FakeAuthSession(), api: ScriptedSearchAPI(fallback: .success, gate: gate))

        // Load A parks in flight before load B starts; tickets follow arrival
        // order, so A holds ticket 0 and B holds ticket 1.
        let taskA = Task { await store.submit("stale-a") }
        try await waitForArrivals(1, on: gate)
        let taskB = Task { await store.submit("stale-b") }
        try await waitForArrivals(2, on: gate)

        // Deliver B's response while A is still parked.
        await gate.release(ticket: 1)
        await taskB.value

        XCTAssertEqual(store.results.map(\.id), ["stale-b"])
        XCTAssertEqual(store.query, "stale-b")
        XCTAssertNil(store.error)
        // The newest load owns the spinner: B's completion clears it even
        // though A is still parked.
        XCTAssertFalse(store.isLoading)

        // A's late response must not regress any visible state.
        await gate.release(ticket: 0)
        await taskA.value

        XCTAssertEqual(store.results.map(\.id), ["stale-b"])
        XCTAssertEqual(store.query, "stale-b")
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }

    func testStaleErrorResponseDoesNotClobberNewerSuccessfulResults() async throws {
        let gate = CallGate()
        // A fails late; B succeeds.
        let api = ScriptedSearchAPI(scripted: [.failure(.network), .success], fallback: .success, gate: gate)
        let store = SearchStore(auth: FakeAuthSession(), api: api)

        let taskA = Task { await store.submit("stale-a") }
        try await waitForArrivals(1, on: gate)
        let taskB = Task { await store.submit("stale-b") }
        try await waitForArrivals(2, on: gate)

        await gate.release(ticket: 1)
        await taskB.value
        XCTAssertEqual(store.results.map(\.id), ["stale-b"])
        XCTAssertNil(store.error)

        // The superseded failure must not overwrite the newer success.
        await gate.release(ticket: 0)
        await taskA.value

        XCTAssertEqual(store.results.map(\.id), ["stale-b"])
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isLoading)
    }
}
