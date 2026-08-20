public enum DownloadStatus: String, Codable, Sendable, Hashable {
    case idle
    case resolving
    case queued
    case downloading
    case paused
    case validating
    case muxing
    case finalizing
    case waitingForRetry
    case reResolving
    case completed
    case failed
}

public enum DownloadError: String, Error, Equatable, Sendable {
    case noAllowedStream
    case requestedQualityUnavailable
    case transportFailed
    case validationFailed
    case finalizationFailed
    case muxFailed
    case expiredMediaURL
    case cancelled
    case interrupted
    case storageRefused
    case unknown
}

/// Explicit, observable download state machine. Background transfer, file
/// finalization, muxing, and validation are the app-layer concern; this model
/// encodes valid transitions so coordinator logic and UI can be tested
/// deterministically and recover from failures predictably.
public struct DownloadState: Sendable, Hashable {
    public var status: DownloadStatus
    public var error: DownloadError?
    public var bytesDownloaded: Int64
    public var totalBytes: Int64

    public init(
        status: DownloadStatus = .idle,
        error: DownloadError? = nil,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0
    ) {
        self.status = status
        self.error = error
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
    }

    public enum TransitionError: Error, Equatable, Sendable {
        case invalidTransition
    }

    @discardableResult
    public mutating func transition(to next: DownloadStatus) throws(TransitionError) {
        guard isValid(next: next, from: status) else {
            throw TransitionError.invalidTransition
        }
        status = next
        if next != .failed {
            error = nil
        }
        return ()
    }

    private func isValid(next: DownloadStatus, from current: DownloadStatus) -> Bool {
        switch (current, next) {
        case (.idle, .queued), (.idle, .resolving), (.idle, .failed):
            return true
        case (.resolving, .queued), (.resolving, .failed):
            return true
        case (.queued, .downloading), (.queued, .failed):
            return true
        case (.downloading, .paused), (.downloading, .validating),
             (.downloading, .waitingForRetry), (.downloading, .failed):
            return true
        case (.paused, .downloading), (.paused, .failed):
            return true
        case (.validating, .finalizing), (.validating, .muxing), (.validating, .failed):
            return true
        case (.muxing, .finalizing), (.muxing, .failed):
            return true
        case (.finalizing, .completed), (.finalizing, .failed):
            return true
        case (.waitingForRetry, .downloading), (.waitingForRetry, .failed):
            return true
        case (.reResolving, .queued), (.reResolving, .failed):
            return true
        case (.failed, .idle), (.failed, .queued), (.failed, .resolving):
            return true
        case (.completed, .idle):
            return true
        default:
            return false
        }
    }
}
