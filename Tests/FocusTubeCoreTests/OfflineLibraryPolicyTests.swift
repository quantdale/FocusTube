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
}
