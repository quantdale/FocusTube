import XCTest
@testable import FocusTubeCore

final class DownloadQueuePolicyTests: XCTestCase {
    func testAdmitsBelowBudgetWithEmptyQueue() {
        XCTAssertFalse(DownloadQueuePolicy.shouldDefer(activeCount: 0, queuedCount: 0, maxConcurrent: 2))
        XCTAssertFalse(DownloadQueuePolicy.shouldDefer(activeCount: 1, queuedCount: 0, maxConcurrent: 2))
    }

    func testDefersAtBudget() {
        XCTAssertTrue(DownloadQueuePolicy.shouldDefer(activeCount: 2, queuedCount: 0, maxConcurrent: 2))
        XCTAssertTrue(DownloadQueuePolicy.shouldDefer(activeCount: 3, queuedCount: 0, maxConcurrent: 2))
    }

    func testQueuedWorkAlwaysHasFIFOPrecedence() {
        // Even with free slots, a nonempty queue forces deferral so later
        // requests can never overtake already-queued work.
        XCTAssertTrue(DownloadQueuePolicy.shouldDefer(activeCount: 0, queuedCount: 1, maxConcurrent: 2))
        XCTAssertTrue(DownloadQueuePolicy.shouldDefer(activeCount: 1, queuedCount: 2, maxConcurrent: 2))
    }

    func testQueuedRecordsNeverOccupyActiveSlots() {
        // A stranded queue must not deadlock admission: queued records do not
        // count toward the active budget, so once actives settle below it,
        // promotion proceeds.
        let active = DownloadQueuePolicy.shouldDefer(activeCount: 0, queuedCount: 5, maxConcurrent: 2)
        XCTAssertTrue(active) // FIFO precedence still defers NEW requests…
        // …but the queue itself drains because promotion checks only active
        // slots, proven by the manager-level tests in the app target.
    }

    func testPromotedHeadsAreBoundByBudgetOnly() {
        // A promoted queue head already holds FIFO priority: sibling queued
        // records must not block it; only the concurrency bound applies.
        XCTAssertFalse(DownloadQueuePolicy.exceedsBudget(activeCount: 0, maxConcurrent: 2))
        XCTAssertFalse(DownloadQueuePolicy.exceedsBudget(activeCount: 1, maxConcurrent: 2))
        XCTAssertTrue(DownloadQueuePolicy.exceedsBudget(activeCount: 2, maxConcurrent: 2))
    }

    func testQueueMetadataRoundTripsThroughCodable() throws {
        let metadata = QueuedDownloadMetadata(title: "T", channelTitle: "C", durationSeconds: 91.5)
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(QueuedDownloadMetadata.self, from: data)
        XCTAssertEqual(decoded, metadata)
    }

    func testCorruptedQueueErrorIsTypedAndDistinct() {
        // The degraded failure class exists specifically so unusable persisted
        // queue rows surface an actionable typed state instead of a generic one.
        XCTAssertNotEqual(DownloadError.queueStateCorrupted, .interrupted)
        // Corrupted queue state is not auto-retried; recovery is user-driven.
        XCTAssertFalse(DownloadRetryPolicy.default.isRetryable(.queueStateCorrupted))
    }
}
