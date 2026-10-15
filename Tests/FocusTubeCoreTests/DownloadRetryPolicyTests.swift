import XCTest
@testable import FocusTubeCore

/// Pins the retry classification for every `DownloadError` case, so a new
/// case or an edit to `retryableErrors` has to update this table on purpose.
final class DownloadRetryPolicyTests: XCTestCase {
    private let all: [DownloadError] = [
        .extractionFailed, .noAllowedStream, .requestedQualityUnavailable,
        .transportFailed, .validationFailed, .finalizationFailed, .muxFailed,
        .expiredMediaURL, .cancelled, .interrupted, .storageRefused,
        .queueStateCorrupted, .unknown,
    ]

    func testOnlyExpiredURLAndTransportFailuresAreRetryable() {
        let retryable = Set(all.filter { DownloadRetryPolicy.default.isRetryable($0) })
        XCTAssertEqual(retryable, [.expiredMediaURL, .transportFailed])
    }

    func testRetryableListIsSubsetOfKnownCases() {
        for e in DownloadRetryPolicy.retryableErrors { XCTAssertTrue(all.contains(e)) }
    }

    func testRetryBoundIsThreeAttemptsTotal() {
        XCTAssertEqual(DownloadRetryPolicy.maxAutomaticRetries, 2)
    }

    func testCancellationIsNeverRetried() {
        XCTAssertFalse(DownloadRetryPolicy.default.isRetryable(.cancelled))
    }
}
