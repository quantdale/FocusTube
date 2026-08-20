import Foundation
import AVFoundation
import AVKit
import CoreMedia
import Observation
import FocusTubeCore

/// Owns the `AVPlayer` / `AVPlayerViewController` lifecycle and maps native
/// playback status into the deterministic `PlaybackState` machine so UI and
/// failure handling stay decoupled from AVFoundation specifics.
///
/// `FocusTubeCore` stays free of AVFoundation; this coordinator is the only
/// place that touches `AVPlayer`. View recreation never resets the player
/// because the coordinator is created once and injected, not reconstructed per
/// view render.
@MainActor
@Observable
public final class PlayerCoordinator {
    public private(set) var state: PlaybackState
    public private(set) var currentStream: MediaStream?
    public private(set) var currentVideoID: String?

    public let player: AVPlayer
    public let playerViewController: AVPlayerViewController

    /// Called periodically with the current playback time (seconds) so callers
    /// can persist resume position without polling.
    public var onProgress: (@MainActor (TimeInterval) -> Void)?

    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private let extractor: MediaExtracting

    public init(extractor: MediaExtracting = YouTubeKitMediaExtractor()) {
        self.extractor = extractor
        self.state = PlaybackState()
        self.player = AVPlayer()
        self.playerViewController = AVPlayerViewController()
        self.playerViewController.player = player
        self.playerViewController.allowsPictureInPictureByDefault = true
    }

    deinit {
        // The coordinator is injected once and lives for the app's lifetime, so
        // no per-lifecycle teardown of AVFoundation observers is required here.
    }

    // MARK: - Selection (delegated to Core policy)

    /// Picks the highest allowed natively playable combined stream. Pure and
    /// deterministic; never selects above 1080p (enforced by Core).
    public func selectOnlineStream(from media: ResolvedMedia) -> MediaStream? {
        MediaStreamFilter.selectOnlineStream(media)
    }

    // MARK: - Native status mapping (deterministic, testable)

    public static func playbackError(for status: AVPlayerItem.Status) -> PlaybackError {
        switch status {
        case .readyToPlay:
            return .unknown
        case .failed:
            return .itemFailed
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Loading / playback

    /// Resolves a video ID through the extractor, selects the online stream, and
    /// begins native playback. Extraction and selection failures are typed and
    /// observable via `state`.
    public func loadAndPlay(videoID: String) async {
        currentVideoID = videoID
        do {
            let media = try await extractor.resolve(videoID: videoID)
            guard let stream = selectOnlineStream(from: media) else {
                state = PlaybackState(status: .failed, error: .noPlayableStream)
                return
            }
            prepare(stream: stream)
        } catch {
            state = PlaybackState(status: .failed, error: mapExtractionFailure(error))
        }
    }

    /// Attaches an already-selected stream to the player and starts playback.
    public func prepare(stream: MediaStream) {
        currentStream = stream
        let item = AVPlayerItem(url: stream.sourceURL)
        playerItem = item
        observe(item: item)
        player.replaceCurrentItem(with: item)
        state = PlaybackState(status: .loading)
        startProgressObserver()
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func resume() {
        player.play()
    }

    /// Plays an already-finalized local media file with no network dependency.
    public func playLocalFile(_ url: URL) {
        let item = AVPlayerItem(url: url)
        playerItem = item
        observe(item: item)
        player.replaceCurrentItem(with: item)
        state = PlaybackState(status: .loading)
        startProgressObserver()
        player.play()
    }

    public func stop() {
        itemObservation?.invalidate()
        timeControlObservation?.invalidate()
        stopProgressObserver()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        currentStream = nil
        currentVideoID = nil
        state = PlaybackState(status: .idle)
    }

    private func startProgressObserver() {
        stopProgressObserver()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1)) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self?.onProgress?(seconds)
            }
        }
    }

    private func stopProgressObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Observation

    private func observe(item: AVPlayerItem) {
        itemObservation?.invalidate()
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in
                self?.handle(itemStatus: observed.status)
            }
        }

        timeControlObservation?.invalidate()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in
                self?.handle(timeControlStatus: observed.timeControlStatus)
            }
        }
    }

    private func handle(itemStatus: AVPlayerItem.Status) {
        switch itemStatus {
        case .readyToPlay:
            if state.status == .loading {
                try? state.transition(to: .ready)
                if player.timeControlStatus == .playing {
                    try? state.transition(to: .playing)
                }
            }
        case .failed:
            state = PlaybackState(status: .failed, error: .itemFailed)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handle(timeControlStatus: AVPlayer.TimeControlStatus) {
        switch timeControlStatus {
        case .playing:
            if state.status == .ready {
                try? state.transition(to: .playing)
            }
        case .paused:
            if state.status == .playing {
                try? state.transition(to: .paused)
            }
        case .waitingToPlayAtSpecifiedRate:
            if state.status == .ready {
                // Stalled while buffering after ready; treat as stalled failure.
                state = PlaybackState(status: .failed, error: .stalled)
            }
        @unknown default:
            break
        }
    }

    private func mapExtractionFailure(_ error: Error) -> PlaybackError {
        if error is ExtractionError {
            return .itemFailed
        }
        return .unknown
    }
}

extension PlayerCoordinator: PlayerCommandTarget {
    public func play() { resume() }
    public func togglePlayPause() {
        if state.status == .playing { pause() } else { resume() }
    }
}
