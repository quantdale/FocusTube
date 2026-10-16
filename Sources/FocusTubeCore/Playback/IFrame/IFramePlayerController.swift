import Foundation

public enum IFramePlaybackPhase: Equatable, Sendable {
    case idle          // no video requested
    case loadingPlayer // embed page/API not ready yet
    case cued          // video cued, not started
    case buffering
    case playing
    case paused
    case ended
    case failed(IFramePlayerError)
}

public struct IFramePlayerState: Equatable, Sendable {
    public var phase: IFramePlaybackPhase = .idle
    public var isPlayerReady = false
    public var videoID: YouTubeVideoID?
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var playbackRate: Double = 1

    public init() {}

    /// Projection onto the legacy coarse status used by existing UI.
    public var legacyStatus: PlaybackStatus {
        switch phase {
        case .idle: return .idle
        case .loadingPlayer, .buffering: return .loading
        case .cued, .ended: return .ready
        case .playing: return .playing
        case .paused: return .paused
        case .failed: return .failed
        }
    }
}

/// Pure state machine for the IFrame player. Intents produce commands for the
/// engine; bridge messages update state. Commands issued before `onReady` are
/// held and flushed on ready (the IFrame API ignores calls before then).
public struct IFramePlayerController: Sendable {
    public private(set) var state = IFramePlayerState()
    private var pendingLoad: IFramePlayerCommand?
    private var pendingPlay = false

    public init() {}

    public enum Intent: Equatable, Sendable {
        case load(YouTubeVideoID, startSeconds: Double, autoplay: Bool)
        case play
        case pause
        case togglePlayPause
        case seek(Double)
        case skip(by: Double)
        case setRate(Double)
        case stop
    }

    /// Returns the commands to send now (possibly empty).
    public mutating func handle(_ intent: Intent) -> [IFramePlayerCommand] {
        switch intent {
        case let .load(id, start, autoplay):
            state.videoID = id
            state.currentTime = max(0, start.isFinite ? start : 0)
            state.duration = 0
            let cmd: IFramePlayerCommand = autoplay ? .load(id, startSeconds: start) : .cue(id, startSeconds: start)
            guard state.isPlayerReady else {
                state.phase = .loadingPlayer
                pendingLoad = cmd
                pendingPlay = false
                return []
            }
            state.phase = autoplay ? .buffering : .cued
            return [cmd]
        case .play:
            guard state.videoID != nil else { return [] }
            if case .failed = state.phase { return [] }
            guard state.isPlayerReady else { pendingPlay = true; return [] }
            return [.play]
        case .pause:
            guard state.isPlayerReady else { pendingPlay = false; return [] }
            return state.phase == .playing || state.phase == .buffering ? [.pause] : []
        case .togglePlayPause:
            return handle(state.phase == .playing || state.phase == .buffering ? .pause : .play)
        case let .seek(s):
            guard state.isPlayerReady, state.videoID != nil, s.isFinite else { return [] }
            let clamped = state.duration > 0 ? min(max(0, s), state.duration) : max(0, s)
            state.currentTime = clamped
            return [.seek(seconds: clamped)]
        case let .skip(delta):
            return handle(.seek(state.currentTime + delta))
        case let .setRate(r):
            guard state.isPlayerReady, r.isFinite, r > 0 else { return [] }
            return [.setPlaybackRate(r)]
        case .stop:
            pendingLoad = nil
            pendingPlay = false
            let wasActive = state.isPlayerReady && state.videoID != nil
            let ready = state.isPlayerReady
            state = IFramePlayerState()
            state.isPlayerReady = ready
            return wasActive ? [.stop] : []
        }
    }

    /// Applies a bridge message; returns commands to flush (e.g. deferred load on ready).
    public mutating func apply(_ message: IFrameBridgeMessage) -> [IFramePlayerCommand] {
        switch message {
        case .ready:
            state.isPlayerReady = true
            var out: [IFramePlayerCommand] = []
            if let load = pendingLoad {
                out.append(load)
                if case .load = load { state.phase = .buffering } else { state.phase = .cued }
            } else if state.phase == .loadingPlayer {
                state.phase = .idle
            }
            if pendingPlay, state.videoID != nil { out.append(.play) }
            pendingLoad = nil
            pendingPlay = false
            return out
        case let .stateChange(code):
            guard state.videoID != nil else { return [] }
            switch code {
            case .unstarted: if state.phase != .buffering { state.phase = .cued }
            case .cued: state.phase = .cued
            case .buffering: state.phase = .buffering
            case .playing: state.phase = .playing
            case .paused: state.phase = .paused
            case .ended:
                state.phase = .ended
                if state.duration > 0 { state.currentTime = state.duration }
            }
            return []
        case let .error(err):
            state.phase = .failed(err)
            return []
        case let .playbackRateChange(r):
            state.playbackRate = r
            return []
        case let .progress(t, d):
            state.duration = d
            state.currentTime = d > 0 ? min(t, d) : t
            return []
        }
    }
}
