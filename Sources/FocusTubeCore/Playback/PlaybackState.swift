public enum PlaybackStatus: String, Codable, Sendable, Hashable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case failed
}

public enum PlaybackError: Error, Equatable, Sendable {
    case noPlayableStream
    case itemFailed
    case stalled
    case unknown
}

/// Explicit, observable playback state machine. AVFoundation observation is the
/// app-layer concern; this model encodes valid transitions so UI and coordinator
/// logic can be tested deterministically and recover from failures predictably.
public struct PlaybackState: Sendable {
    public var status: PlaybackStatus
    public var error: PlaybackError?

    public init(status: PlaybackStatus = .idle, error: PlaybackError? = nil) {
        self.status = status
        self.error = error
    }

    public enum TransitionError: Error, Equatable, Sendable {
        case invalidTransition
    }

    @discardableResult
    public mutating func transition(to next: PlaybackStatus) throws TransitionError {
        guard isValid(next: next, from: status) else {
            throw TransitionError.invalidTransition
        }
        status = next
        if next != .failed {
            error = nil
        }
        return ()
    }

    private func isValid(next: PlaybackStatus, from current: PlaybackStatus) -> Bool {
        switch (current, next) {
        case (.idle, .loading), (.idle, .failed):
            return true
        case (.loading, .ready), (.loading, .failed):
            return true
        case (.ready, .playing), (.ready, .failed):
            return true
        case (.playing, .paused), (.playing, .failed):
            return true
        case (.paused, .playing), (.paused, .failed):
            return true
        case (.failed, .idle), (.failed, .loading):
            return true
        default:
            return false
        }
    }
}
