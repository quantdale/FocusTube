import XCTest
@testable import FocusTubeCore

/// DDV2-07: deliberate recent-search policy — ordering, dedupe, bound,
/// suggestions, removal. Purely local; typing never implies network work.
final class SearchRecentsPolicyTests: XCTestCase {
    private func entry(_ query: String, minutesAgo: Int) -> RecentQueryEntry {
        RecentQueryEntry(query: query, updatedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(minutesAgo) * 60))
    }

    func testRecordingInsertsAtFrontAndDeduplicatesCaseInsensitively() {
        var recents = [entry("lofi mix", minutesAgo: 30), entry("documentary", minutesAgo: 10)]
        recents = SearchRecentsPolicy.record(recents, newQuery: "Lofi Mix", now: Date())
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents.first?.query, "Lofi Mix", "most recent recording leads")
        XCTAssertEqual(recents.last?.query, "documentary")
        XCTAssertEqual(
            Set(recents.map { $0.query.lowercased() }).count,
            recents.count,
            "case-insensitive dedupe must not keep both spellings"
        )
    }

    func testHistoryIsHardBounded() {
        var recents: [RecentQueryEntry] = []
        for index in 0..<25 {
            recents = SearchRecentsPolicy.record(recents, newQuery: "q\(index)", now: Date())
        }
        XCTAssertEqual(recents.count, SearchRecentsPolicy.maxEntries)
        XCTAssertEqual(recents.first?.query, "q24", "newest survives the bound")
        XCTAssertEqual(recents.last?.query, "q15", "oldest entries fall off")
    }

    /// HB-030: a custom cap BELOW the current entry count must trim the tail
    /// (oldest) while keeping the newest — the parameterized bound is real,
    /// not decorative.
    func testCustomMaxEntriesBelowExistingCountTrimsOldest() {
        let seeded = (0..<10).map { entry("e\($0)", minutesAgo: $0) } // e0 newest
        let trimmed = SearchRecentsPolicy.record(seeded, newQuery: "fresh", now: Date(), maxEntries: 3)
        XCTAssertEqual(trimmed.map(\.query), ["fresh", "e0", "e1"])
        XCTAssertEqual(trimmed.count, 3)

        // Cap of zero degenerates to just the new query being dropped too.
        let emptied = SearchRecentsPolicy.record(seeded, newQuery: "fresh", now: Date(), maxEntries: 0)
        XCTAssertTrue(emptied.isEmpty)
    }

    func testBlankQueriesNeverRecord() {
        var recents = [entry("keep", minutesAgo: 1)]
        let unchanged = SearchRecentsPolicy.record(recents, newQuery: "   ", now: Date())
        XCTAssertEqual(unchanged.map(\.query), ["keep"])
    }

    func testClearRemovesEverything() {
        var recents = [entry("a", minutesAgo: 3), entry("b", minutesAgo: 1)]
        recents.removeAll()
        XCTAssertTrue(SearchRecentsPolicy.suggestions(for: "a", in: recents).isEmpty)
    }

    func testSuggestionsMatchSubstringWithoutNetwork() {
        // Input is assumed newest-first (the persisted store guarantees this).
        let recents = [entry("SPACE engine", minutesAgo: 1), entry("cooking basics", minutesAgo: 2), entry("space documentary", minutesAgo: 5)]
        let hits = SearchRecentsPolicy.suggestions(for: " space", in: recents)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.first?.query, "SPACE engine", "suggestions are newest-first")
    }

    func testRemoveIsCaseInsensitiveAndPreservesOrder() {
        let recents = [entry("Alpha", minutesAgo: 3), entry("beta", minutesAgo: 1)]
        let remaining = SearchRecentsPolicy.remove("ALPHA", from: recents)
        XCTAssertEqual(remaining.map(\.query), ["beta"])
    }
}
