import Foundation

/// Single source of truth for the download auto-retry policy.
///
/// Shipped semantics (reconciled with docs/03 in DDV2-02): up to THREE
/// transfer attempts total — the initial attempt plus `maxAutomaticRetries`
/// bounded re-attempts. Every retry re-resolves fresh stream URLs through
/// `MediaExtracting`; persisted/previous URLs are never replayed. Only the
/// retryable failure classes below trigger an automatic retry; everything
/// else surfaces immediately as a typed user-facing failure. The bound is
/// structural: the retry loop consumes a decreasing counter and can never
/// spin unboundedly.
public struct DownloadRetryPolicy: Sendable {
    /// Automatic re-attempts performed by `DownloadService` after the initial
    /// transfer attempt (so maxAutomaticRetries == 2 means 3 attempts total).
    public static let maxAutomaticRetries = 2

    /// Failure classes worth automatic retries: signed media URLs expire by
    /// design, and plain transport faults are frequently transient.
    public static let retryableErrors: [DownloadError] = [.expiredMediaURL, .transportFailed]

    public init() {}

    public func isRetryable(_ error: DownloadError) -> Bool {
        Self.retryableErrors.contains(error)
    }

    /// Shared default instance; the policy is currently stateless.
    public static let `default` = DownloadRetryPolicy()
}
