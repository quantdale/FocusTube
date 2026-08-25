import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// H3-04 / HB-027: the videoID→resume-fraction projection replaces per-card
/// full-history scans. Semantics must match what the old per-row helper
/// computed: only genuinely in-progress entries with a usable duration,
/// clamped to 0...1.
@MainActor
final class ResumeFractionProjectionTests: XCTestCase {
    private func makeStore() throws -> LibraryStore {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return LibraryStore(context: ModelContext(container))
    }

    func testProjectionIncludesOnlyInProgressEntriesWithUsableDuration() throws {
        let store = try makeStore()

        store.recordProgress(videoID: "half", title: "Half", channelTitle: "C",
                             position: 50, duration: 200, completed: false)
        store.recordProgress(videoID: "done", title: "Done", channelTitle: "C",
                             position: 200, duration: 200, completed: true)
        store.recordProgress(videoID: "nodur", title: "NoDur", channelTitle: "C",
                             position: 30, duration: nil, completed: false)
        store.recordProgress(videoID: "zerodur", title: "Zero", channelTitle: "C",
                             position: 30, duration: 0, completed: false)
        store.recordProgress(videoID: "clamped", title: "Clamped", channelTitle: "C",
                             position: 500, duration: 100, completed: false)

        let fractions = store.resumeFractions()

        XCTAssertEqual(fractions["half"], 0.25)
        XCTAssertNil(fractions["done"], "completed entries are not continue-watching candidates")
        XCTAssertNil(fractions["nodur"])
        XCTAssertNil(fractions["zerodur"])
        XCTAssertEqual(fractions["clamped"], 1.0, "overrun positions clamp to 1")
    }

    func testProjectionInvalidatesOnMutationGenerationAndTracksWrites() throws {
        let store = try makeStore()
        store.recordProgress(videoID: "v1", title: "V1", channelTitle: "C",
                             position: 10, duration: 100, completed: false)
        XCTAssertEqual(store.resumeFractions().keys.sorted(), ["v1"])

        // A new write bumps the revision; the next read must reflect it.
        store.recordProgress(videoID: "v2", title: "V2", channelTitle: "C",
                             position: 80, duration: 100, completed: false)
        XCTAssertEqual(store.resumeFractions().keys.sorted(), ["v1", "v2"])

        // Completion removes an entry from continue-watching semantics.
        store.recordProgress(videoID: "v1", title: "V1", channelTitle: "C",
                             position: 100, duration: 100, completed: true)
        XCTAssertEqual(store.resumeFractions().keys.sorted(), ["v2"])

        // Deletion also invalidates.
        store.removeHistory(videoID: "v2")
        XCTAssertTrue(store.resumeFractions().isEmpty)
    }
}
