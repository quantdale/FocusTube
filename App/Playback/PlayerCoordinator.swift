import Foundation
import Observation
import FocusTubeCore

/// ADR-0007: app-facing playback coordinator over a `PlayerEngine` (the
/// official YouTube IFrame Player in production). No stream extraction.
/// Keeps the public surface the views already use (`state`, `loadAndPlay`,
/// `onProgress`, Now Playing fields, `PlayerCommandTarget`).
@MainActor
@Observable
public final class PlayerCoordinator {
    public private(set) var state = PlaybackState()
    /// Detailed IFrame error for the failure overlay (e.g. embedding disabled).
    public private(set) var iframeError: IFramePlayerError?
    public private(set) var currentVideoID: String?
    public private(set) var engineState = IFramePlayerState()

    /// Extraction no longer happens; kept only so the compiled-out legacy
    /// download code still type-checks. Always nil. Removed in phase 3.
    public var lastResolvedMedia: ResolvedMedia? { nil }

    public var onProgress: (@MainActor (TimeInterval) -> Void)?
    public var onNowPlayingChanged: (@MainActor () -> Void)?
    public var nowPlayingTitle: String?
    public var nowPlayingArtist: String?

    let engine: any PlayerEngine
    private let resolveID: (String) -> YouTubeVideoID?
    @ObservationIgnored private var lastReportedProgress: Double = -.infinity
    /// Minimum seconds between `onProgress` calls (engine ticks every 0.5 s).
    let progressInterval: Double

    public init(
        engine: any PlayerEngine,
        progressInterval: Double = 5,
        resolveID: @escaping (String) -> YouTubeVideoID? = { YouTubeVideoID($0) }
    ) {
        self.engine = engine
        self.progressInterval = progressInterval
        self.resolveID = resolveID
        engine.onStateChange = { [weak self] s in self?.engineDidChange(s) }
    }

    public var nowPlayingSnapshot: NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: nowPlayingTitle,
            artist: nowPlayingArtist,
            duration: engineState.duration,
            currentTime: engineState.currentTime,
            rate: engineState.phase == .playing ? engineState.playbackRate : 0
        )
    }

    public func loadAndPlay(videoID: String, resumeAt: TimeInterval? = nil) async {
        currentVideoID = videoID
        iframeError = nil
        lastReportedProgress = -.infinity
        guard let id = resolveID(videoID) else {
            state = PlaybackState(status: .failed, error: .noPlayableStream)
            onNowPlayingChanged?()
            return
        }
        let start = (resumeAt ?? 0) > 0.5 ? resumeAt! : 0
        state = PlaybackState(status: .loading)
        engine.load(id, startSeconds: start, autoplay: true)
    }

    public func pause() { engine.pause() }
    public func resume() { engine.play() }

    public func stop() {
        engine.stop()
        currentVideoID = nil
        iframeError = nil
        state = PlaybackState(status: .idle)
        onNowPlayingChanged?()
    }

    func engineDidChange(_ s: IFramePlayerState) {
        let previous = engineState
        engineState = s
        if case let .failed(err) = s.phase {
            iframeError = err
            state = PlaybackState(status: .failed, error: Self.playbackError(for: err))
        } else if currentVideoID != nil || s.phase == .idle {
            state = PlaybackState(status: s.legacyStatus)
        }
        reportProgressIfNeeded(previous: previous, current: s)
        onNowPlayingChanged?()
    }

    private func reportProgressIfNeeded(previous: IFramePlayerState, current: IFramePlayerState) {
        guard currentVideoID != nil, current.currentTime > 0 else { return }
        let phaseSettled = previous.phase != current.phase
            && (current.phase == .paused || current.phase == .ended)
        if phaseSettled || abs(current.currentTime - lastReportedProgress) >= progressInterval {
            lastReportedProgress = current.currentTime
            onProgress?(current.currentTime)
        }
    }

    public static func playbackError(for error: IFramePlayerError) -> PlaybackError {
        switch error {
        case .embeddingNotAllowed, .videoNotFound, .invalidParameter: return .noPlayableStream
        case .html5Error: return .itemFailed
        case .unknown: return .unknown
        }
    }
}

extension PlayerCoordinator: PlayerCommandTarget {
    public func play() { resume() }
    public func togglePlayPause() {
        if state.status == .playing { pause() } else { resume() }
    }
    public func seek(to seconds: TimeInterval) { engine.seek(to: seconds) }
}
