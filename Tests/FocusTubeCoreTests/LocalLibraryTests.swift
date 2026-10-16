import XCTest
@testable import FocusTubeCore

final class LocalLibraryTests: XCTestCase {
    let a = YouTubeChannelID("UCaaaaaaaaaaaaaaaaaaaaaa")!
    let b = YouTubeChannelID("UCbbbbbbbbbbbbbbbbbbbbbb")!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func video(_ id: String, _ title: String = "T", channel: String = "C", duration: Int? = nil) -> VideoSummary {
        VideoSummary(id: id, title: title, channelTitle: channel, durationSeconds: duration, publishedAt: nil, thumbnailURL: nil, description: nil)
    }

    func testSubscriptionsDedupeAndSort() {
        var lib = LocalLibrary()
        XCTAssertTrue(lib.subscribe(b, title: "beta", now: t0))
        XCTAssertTrue(lib.subscribe(a, title: "Alpha", now: t0))
        XCTAssertFalse(lib.subscribe(a, title: "Alpha 2", now: t0))
        XCTAssertEqual(lib.subscriptions.map(\.title), ["Alpha 2", "beta"])
        XCTAssertTrue(lib.isSubscribed(a))
        lib.unsubscribe(a)
        XCTAssertFalse(lib.isSubscribed(a))
    }

    func testWatchLaterRefusesShortsAndDuplicates() {
        var lib = LocalLibrary()
        XCTAssertTrue(lib.addToWatchLater(video("v1")))
        XCTAssertFalse(lib.addToWatchLater(video("v1")))
        XCTAssertFalse(lib.addToWatchLater(video("s1", duration: 59)))
        XCTAssertTrue(lib.addToWatchLater(video("v2", duration: 600)))
        XCTAssertEqual(lib.watchLater.map(\.id), ["v2", "v1"])
        lib.removeFromWatchLater("v1")
        XCTAssertEqual(lib.watchLater.map(\.id), ["v2"])
    }

    func testHistoryResumeRulesAndCap() {
        var lib = LocalLibrary()
        lib.recordProgress(video("v1"), position: 5, duration: 600, now: t0)
        XCTAssertNil(lib.resumePosition(for: "v1"), "<10 s is not worth resuming")
        lib.recordProgress(video("v1"), position: 120, duration: 600, now: t0)
        XCTAssertEqual(lib.resumePosition(for: "v1"), 120)
        XCTAssertEqual(lib.history.count, 1)
        lib.recordProgress(video("v1"), position: 580, duration: 600, now: t0)
        XCTAssertNil(lib.resumePosition(for: "v1"), "near the end restarts")
        lib.recordProgress(video("v2"), position: .nan, duration: nil, now: t0)
        XCTAssertEqual(lib.history.count, 1)
        for i in 0..<(LocalLibrary.historyLimit + 5) { lib.recordProgress(video("x\(i)"), position: 1, duration: nil, now: t0) }
        XCTAssertEqual(lib.history.count, LocalLibrary.historyLimit)
        XCTAssertEqual(lib.history.first?.video.id, "x\(LocalLibrary.historyLimit + 4)")
    }

    func testLocalSearch() {
        var lib = LocalLibrary()
        lib.addToWatchLater(video("v1", "Swift Concurrency Deep Dive", channel: "Apple"))
        lib.recordProgress(video("v2", "Café talk", channel: "Paris"), position: 30, duration: nil, now: t0)
        let extra = [video("v3", "Concurrency in Rust", channel: "Ferris"), video("v1", "dup")]
        XCTAssertEqual(lib.search("concurrency", in: extra).map(\.id), ["v1", "v3"])
        XCTAssertEqual(lib.search("CAFE").map(\.id), ["v2"])
        XCTAssertEqual(lib.search("swift apple").map(\.id), ["v1"])
        XCTAssertEqual(lib.search("   "), [])
    }

    func testPlaylists() {
        var lib = LocalLibrary()
        let p = YouTubePlaylistID("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")!
        XCTAssertTrue(lib.savePlaylist(p, title: "Mix", now: t0))
        XCTAssertFalse(lib.savePlaylist(p, title: "", now: t0))
        XCTAssertEqual(lib.playlists.first?.title, "Mix")
        lib.removePlaylist(p)
        XCTAssertTrue(lib.playlists.isEmpty)
    }

    func testStoreRoundTripAndCorruptionRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ft-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalLibraryStore(fileURL: dir.appendingPathComponent("library.json"))
        let (empty, o1) = await store.load()
        XCTAssertEqual(o1, .empty)
        XCTAssertEqual(empty, LocalLibrary())
        var lib = LocalLibrary()
        lib.subscribe(a, title: "A", now: t0)
        lib.recordProgress(video("v1"), position: 42, duration: 100, now: t0)
        try await store.save(lib)
        let (loaded, o2) = await store.load()
        XCTAssertEqual(o2, .loaded)
        XCTAssertEqual(loaded, lib)
        try Data("{broken".utf8).write(to: store.fileURL)
        let (recovered, o3) = await store.load()
        XCTAssertEqual(o3, .recoveredFromCorruption)
        XCTAssertEqual(recovered, LocalLibrary())
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path + ".corrupt"))
    }

    func testInvalidChannelIDFailsDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode([YouTubeChannelID].self, from: Data(#"["nope"]"#.utf8)))
    }
}

final class PublicFeedAggregatorTests: XCTestCase {
    let a = YouTubeChannelID("UC_x5XG1OV2P6uZZ5FSM9Ttw")!
    let b = YouTubeChannelID("UCbbbbbbbbbbbbbbbbbbbbbb")!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class CountingHTTP: HTTPFetching, @unchecked Sendable {
        let lock = NSLock()
        var calls: [String] = []
        let responses: [String: (Data, Int)]
        init(_ r: [String: (Data, Int)]) { responses = r }
        private func record(_ s: String) { lock.lock(); calls.append(s); lock.unlock() }
        func get(_ url: URL) async throws -> (data: Data, status: Int) {
            record(url.absoluteString)
            return responses[url.absoluteString].map { ($0.0, $0.1) } ?? (Data(), 404)
        }
    }

    func subs(_ ids: [YouTubeChannelID]) -> [LocalSubscription] { ids.map { LocalSubscription(channelID: $0, title: "", addedAt: t0) } }

    func feedB() -> String {
        FeedFixtures.playlist  // one entry dQw4w9WgXcQ (dup of channel A's), 2026-01-01
            .replacingOccurrences(of: "dQw4w9WgXcQ", with: "bbbbbbbbbbb")
    }

    func testMergesFiltersShortsDedupesAndSorts() async {
        let http = CountingHTTP([
            PublicEndpoints.channelFeed(a).absoluteString: (Data(FeedFixtures.channel.utf8), 200),
            PublicEndpoints.channelFeed(b).absoluteString: (Data(feedB().utf8), 200),
        ])
        let agg = PublicFeedAggregator(client: PublicFeedClient(http: http))
        let snap = await agg.refresh(subs([a, b]), now: t0)
        XCTAssertEqual(snap.videos.map(\.id), ["dQw4w9WgXcQ", "bbbbbbbbbbb"], "newest first, /shorts/ entry hidden")
        XCTAssertEqual(snap.hiddenShorts, 1)
        XCTAssertTrue(snap.failures.isEmpty)
    }

    func testRefreshIntervalAndFailuresKeepCache() async {
        let url = PublicEndpoints.channelFeed(a).absoluteString
        let http = CountingHTTP([url: (Data(FeedFixtures.channel.utf8), 200)])
        let agg = PublicFeedAggregator(client: PublicFeedClient(http: http), refreshInterval: 900)
        _ = await agg.refresh(subs([a, b]), now: t0)
        XCTAssertEqual(http.calls.count, 2)
        let snap = await agg.refresh(subs([a, b]), now: t0.addingTimeInterval(60))
        XCTAssertEqual(http.calls.count, 3, "only the failed feed (b) is retried within the interval")
        XCTAssertEqual(snap.failures[b.rawValue], .notFound)
        XCTAssertEqual(snap.videos.count, 1)
        _ = await agg.refresh(subs([a, b]), now: t0.addingTimeInterval(60), force: true)
        XCTAssertEqual(http.calls.count, 5)
    }

    func testUnsubscribedFeedsDropOutAndKnownShortsHide() async {
        let http = CountingHTTP([PublicEndpoints.channelFeed(a).absoluteString: (Data(FeedFixtures.channel.utf8), 200)])
        let agg = PublicFeedAggregator(client: PublicFeedClient(http: http))
        _ = await agg.refresh(subs([a]), now: t0)
        await agg.learnDuration("dQw4w9WgXcQ", seconds: 120)
        var snap = await agg.cachedSnapshot()
        XCTAssertTrue(snap.videos.isEmpty, "duration ≤180 s learned from the player hides it")
        XCTAssertEqual(snap.hiddenShorts, 2)
        snap = await agg.refresh([], now: t0)
        XCTAssertTrue(snap.videos.isEmpty)
        XCTAssertEqual(snap.hiddenShorts, 0)
    }

    func testPortraitOEmbedMarksShortAndDurationAnnotates() async {
        let http = CountingHTTP([PublicEndpoints.channelFeed(a).absoluteString: (Data(FeedFixtures.channel.utf8), 200)])
        let agg = PublicFeedAggregator(client: PublicFeedClient(http: http))
        _ = await agg.refresh(subs([a]), now: t0)
        await agg.learnDuration("dQw4w9WgXcQ", seconds: 1200)
        var snap = await agg.cachedSnapshot()
        XCTAssertEqual(snap.videos.first?.durationSeconds, 1200)
        await agg.learn(OEmbedMetadata(title: "", authorName: "", authorURL: nil, thumbnailURL: nil, width: 113, height: 200), for: "dQw4w9WgXcQ")
        snap = await agg.cachedSnapshot()
        XCTAssertTrue(snap.videos.isEmpty)
    }
}
