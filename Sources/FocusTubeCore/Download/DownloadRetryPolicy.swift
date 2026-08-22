import Foundation

/// Single source of truth for the download auto-retry policy. Documents the
/// CURRENT shipped semantics: exactly one bounded automatic retry re-resolves
/// fresh stream URLs for retryable transport-class failures before surfacing
/// failure to the user. NOTE: docs/03 describes up to 3 attempts; that delta
/// is a recorded spec question pending owner decision — do not change the
/// attempt count here without an accepted decision.
public struct DownloadRetryPolicy: Sendable {
    /// Automatic re-attempts performed by `DownloadService` after the initial
    /// transfer attempt (so one retry == 2 attempts total today).
    public static let maxAutomaticRetries = 1

    /// Failure classes worth one automatic retry: signed media URLs expire by
    /// design, and plain transport faults are frequently transient.
    public static let retryableErrors: [DownloadError] = [.expiredMediaURL, .transportFailed]

    public init() {}

    public func isRetryable(_ error: DownloadError) -> Bool {
        Self.retryableErrors.contains(error)
    }

    /// Shared default instance; the policy is currently stateless.
    public static let `default` = DownloadRetryPolicy()
}
