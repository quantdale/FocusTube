import XCTest
@testable import FocusTubeCore

/// DDV2-02: offline-library organization policy — sorting, channel grouping,
/// totals, and deterministic human-readable sizes.
final class OfflineLibraryPolicyTests: XCTestCase {
    private func item(
        _ id: String,
        channel: String,
        size: Int64,
        daysAgo: Int,
        resolution: Int = 720
    ) -> OfflineMediaSummary {
        OfflineMediaSummary(
            id: id,
            title: "Title \(id)",
            channelTitle: channel,
            resolution: resolution,
            sizeBytes: size,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(daysAgo) * 86_400)
        )
    }

    private var fixtures: [OfflineMediaSummary] {
        [
            item("a", channel: "alpha", size: 300, daysAgo: 1),
            item("b", channel: "Beta", size: 900, daysAgo: 5),
            item("c", channel: "ALPHA", size: 100, daysAgo: 2),
            item("d", channel: "gamma", size: 700, daysAgo: 0)
        ]
    }

    func testNewestFirstOrdering() {
        let sorted = OfflineLibraryPolicy.sorted(fixtures, by: .newestFirst)
        XCTAssertEqual(sorted.map(\.id), ["d", "a", "c", "b"])
    }

    func testLargestFirstOrdering() {
        let sorted = OfflineLibraryPolicy.sorted(fixtures, by: .largestFirst)
        XCTAssertEqual(sorted.map(\.id), ["b", "d", "a", "c"])
    }

    func testChannelGroupingIsCaseInsensitiveAndNewestChannelLeads() {
        let grouped = OfflineLibraryPolicy.groupedByChannel(fixtures)
        // alpha (newest item 1 day ago) before gamma (today)? gamma's item is
        // newest overall (0 days) → gamma first, then alpha (case-merged),
        // then Beta.
        XCTAssertEqual(grouped.map(\.channel), ["gamma", "alpha", "Beta"])
        XCTAssertEqual(grouped[1].items.map(\.id), ["a", "c"], "within a channel: newest first")
        // Case-insensitive merge: ALPHA and alpha collapse into one group of two.
        XCTAssertEqual(grouped.count, 3)
    }

    func testTotalBytesSumsLibrary() {
        XCTAssertEqual(OfflineLibraryPolicy.totalBytes(fixtures), 2000)
        XCTAssertEqual(OfflineLibraryPolicy.totalBytes([]), 0)
    }

    func testHumanReadableFileSizeIsDeterministic() {
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(0), "0 B")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(1023), "1023 B")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(1024), "1 KB")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(1536), "1.5 KB")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(1_048_576), "1 MB")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(2_500_000), "2.4 MB")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(3_221_225_472), "3 GB")
        XCTAssertEqual(OfflineLibraryPolicy.formattedFileSize(1_610_612_736), "1.5 GB")
    }

    // MARK: - HB-020 total deterministic ordering

    private func tieItem(_ id: String, channel: String, size: Int64, at time: TimeInterval) -> OfflineMediaSummary {
        OfflineMediaSummary(
            id: id,
            title: "Title \(id)",
            channelTitle: channel,
            resolution: 720,
            sizeBytes: size,
            createdAt: Date(timeIntervalSince1970: time)
        )
    }

    func testEqualTimestampsBreakTiesByIdDeterministically() {
        let now = 1_900_000_000
        let ties = [
            tieItem("zz", channel: "c", size: 10, at: Double(now)),
            tieItem("aa", channel: "c", size: 10, at: Double(now)),
            tieItem("mm", channel: "c", size: 10, at: Double(now))
        ]
        for order in [OfflineLibraryPolicy.SortOrder.newestFirst, .largestFirst, .byChannelThenNewest] {
            let sorted = OfflineLibraryPolicy.sorted(ties, by: order)
            XCTAssertEqual(sorted.map(\.id), ["aa", "mm", "zz"], "\(order) ties resolve by id")
            // Reverse the input; the output must not move.
            let reversed = OfflineLibraryPolicy.sorted(ties.reversed(), by: order)
            XCTAssertEqual(reversed.map(\.id), ["aa", "mm", "zz"])
        }
    }

    func testNegativeSizesOrderDeterministicallyWithIdTiebreak() {
        let now = 1_900_000_000
        let weird = [
            tieItem("b", channel: "c", size: -5, at: Double(now)),
            tieItem("a", channel: "c", size: -5, at: Double(now)),
            tieItem("c", channel: "c", size: 50, at: Double(now))
        ]
        let sorted = OfflineLibraryPolicy.sorted(weird, by: .largestFirst)
        XCTAssertEqual(sorted.map(\.id), ["c", "a", "b"], "positive leads; equal negatives break by id")
    }

    func testEmptyChannelTitlesGroupTogetherDeterministically() {
        let now = 1_900_000_000
        let mixed = [
            tieItem("x1", channel: "", size: 10, at: Double(now - 100)),
            tieItem("x2", channel: "   ", size: 20, at: Double(now)),
            tieItem("y1", channel: "Named", size: 30, at: Double(now - 200))
        ]
        let grouped = OfflineLibraryPolicy.groupedByChannel(mixed)
        // Blank titles merge into one group (whitespace is NOT lowercased to
        // empty — '   ' stays its own canonical key).
        XCTAssertEqual(grouped.count, 3, "empty vs whitespace vs named are distinct groups")
        XCTAssertEqual(grouped.map { $0.items.first?.id ?? "" }, ["x2", "x1", "y1"])
    }

    func testGroupingTieOnNewestTimestampBreaksByChannelName() {
        let now = 1_900_000_000
        let tied = [
            tieItem("b1", channel: "zeta", size: 10, at: Double(now)),
            tieItem("a1", channel: "Alpha", size: 10, at: Double(now)),
            tieItem("a0", channel: "Alpha", size: 10, at: Double(now - 50))
        ]
        let grouped = OfflineLibraryPolicy.groupedByChannel(tied)
        XCTAssertEqual(grouped.map(\.channel).map { $0.lowercased() }, ["alpha", "zeta"],
                       "equal newest timestamps order channels case-insensitively by name")
        XCTAssertEqual(grouped[0].items.map(\.id), ["a1", "a0"])
    }
}
