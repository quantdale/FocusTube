import XCTest
@testable import FocusTubeCore

/// HB-017: the explicit DownloadState transition table is now authoritative —
/// every event-path write routes through `transition(to:)`, dead statuses were
/// removed, and the full validity matrix is pinned so future invalid-transition
/// regressions surface here before they reach product code.
final class DownloadStateTests: XCTestCase {
    private func make(_ status: DownloadStatus, error: DownloadError? = nil) -> DownloadState {
        var state = DownloadState()
        state.status = status
        state.error = error
        return state
    }

    func testFullTransitionMatrixMatchesTheModeledTable() {
        let all: [DownloadStatus] = [
            .idle, .resolving, .queued, .downloading, .paused,
            .validating, .muxing, .finalizing, .completed, .failed
        ]
        // The exact modeled edges (from -> allowed targets).
        let allowed: [DownloadStatus: Set<DownloadStatus>] = [
            .idle: [.queued, .resolving, .failed],
            .resolving: [.queued, .failed],
            .queued: [.downloading, .failed],
            .downloading: [.paused, .validating, .failed],
            .paused: [.downloading, .failed],
            .validating: [.finalizing, .muxing, .failed],
            .muxing: [.finalizing, .failed],
            .finalizing: [.completed, .failed],
            .completed: [.idle],
            .failed: [.idle, .queued, .resolving]
        ]
        for from in all {
            for to in all {
                var state = make(from)
                if from == .failed { state.error = .transportFailed }
                let result: Void? = try? state.transition(to: to)
                if allowed[from]!.contains(to) {
                    XCTAssertNotNil(result, "\(from.rawValue) -> \(to.rawValue) must be legal")
                    XCTAssertEqual(state.status, to, "\(from.rawValue) -> \(to.rawValue)")
                } else {
                    XCTAssertNil(result, "\(from.rawValue) -> \(to.rawValue) must be rejected")
                }
            }
        }
    }

    func testNonFailedTransitionsClearError() throws {
        var state = make(.downloading, error: .interrupted)
        try state.transition(to: .validating)
        XCTAssertNil(state.error)
    }

    func testFailedTransitionPreservesExplicitErrorAssignment() throws {
        var state = make(.downloading, error: .interrupted)
        // Transitioning INTO .failed never clears the writer's error.
        try state.transition(to: .failed)
        XCTAssertEqual(state.status, .failed)
        XCTAssertEqual(state.error, .interrupted)
    }

    func testInvalidTransitionThrowsWithoutMutatingStatus() {
        var state = make(.completed)
        XCTAssertThrowsError(try state.transition(to: .failed)) { error in
            XCTAssertEqual(error as? DownloadState.TransitionError, .invalidTransition)
        }
        XCTAssertEqual(state.status, .completed, "rejected transition leaves state untouched")
    }
}
