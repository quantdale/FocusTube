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
    /// The most recent successful extraction, so consumers (e.g. the video
    /// page's quality picker) can reuse it instead of extracting again.
    public private(set) var lastResolvedMedia: ResolvedMedia?

    public let player: AVPlayer
    public let playerViewController: AVPlayerViewController

    /// Called periodically with the current playback time (seconds) so callers
    /// can persist resume position without polling.
    public var onProgress: (@MainActor (TimeInterval) -> Void)?

    /// Called whenever Now Playing data may have changed (item change, state
    /// transition, or progress tick); the app layer republishes lock-screen
    /// metadata from `nowPlayingSnapshot` in response.
    public var onNowPlayingChanged: (@MainActor () -> Void)?

    /// Human-readable Now Playing metadata; set by the presenting view before
    /// playback starts.
    public var nowPlayingTitle: String?
    public var nowPlayingArtist: String?

    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    /// Monotonic token bumped on every selection entry point (`loadAndPlay`,
    /// `prepare`, `playLocalFile`, `stop`). Async work captures it at entry and
    /// may only mutate playback state while it is still current, so overlapping
    /// or late-arriving extractions can never clobber newer selections.
    private var generation = 0
    /// Generation-bound watchdog armed while buffering after `.ready`; fires
    /// `.stalled` without needing another KVO delivery to arrive.
    private var stallWatchdog: Task<Void, Never>?
    /// How long `waitingToPlayAtSpecifiedRate` may persist after `.ready`
    /// before playback is declared stalled. Injectable for deterministic tests.
    var stallTimeout: TimeInterval
    private let extractor: MediaExtracting

    public init(extractor: MediaExtracting = YouTubeKitMediaExtractor(), stallTimeout: TimeInterval = 10) {
        self.extractor = extractor
        self.stallTimeout = stallTimeout
        self.state = PlaybackState()
        self.player = AVPlayer()
        self.playerViewController = AVPlayerViewController()
        self.playerViewController.player = player
        self.playerViewController.allowsPictureInPicturePlayback = true
        self.playerViewController.canStartPictureInPictureAutomaticallyFromInline = true
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

    // MARK: - Now Playing snapshot

    /// Current lock-screen metadata derived from the live player. Finite-value
    /// guards keep indefinite/NaN stream durations from poisoning the dictionary.
    public var nowPlayingSnapshot: NowPlayingSnapshot {
        let durationSeconds = player.currentItem.flatMap { item -> Double in
            let seconds = item.duration.seconds
            return seconds.isFinite ? seconds : 0
        } ?? 0
        let currentSeconds = player.currentTime().seconds
        return NowPlayingSnapshot(
            title: nowPlayingTitle,
            artist: nowPlayingArtist,
            duration: durationSeconds,
            currentTime: currentSeconds.isFinite ? currentSeconds : 0,
            rate: Double(player.rate)
        )
    }

    private func notifyNowPlayingChanged() {
        onNowPlayingChanged?()
    }

    // MARK: - Loading / playback

    /// Resolves a video ID through the extractor, selects the online stream, and
    /// begins native playback. Extraction and selection failures are typed and
    /// observable via `state`.
    public func loadAndPlay(videoID: String) async {
        generation += 1
        let gen = generation
        currentVideoID = videoID
        do {
            let media = try await extractor.resolve(videoID: videoID)
            guard gen == generation else { return }
            lastResolvedMedia = media
            guard let stream = selectOnlineStream(from: media) else {
                state = PlaybackState(status: .failed, error: .noPlayableStream)
                return
            }
            prepare(stream: stream)
        } catch {
            guard gen == generation else { return }
            lastResolvedMedia = nil
            state = PlaybackState(status: .failed, error: mapExtractionFailure(error))
        }
    }

    /// Attaches an already-selected stream to the player and starts playback.
    public func prepare(stream: MediaStream) {
        generation += 1
        apply(stream: stream)
    }

    public func pause() {
        player.pause()
    }

    public func resume() {
        player.play()
    }

    /// Plays an already-finalized local media file with no network dependency.
    /// Clears every field tied to prior online playback (stream, video ID,
    /// resolved media, Now Playing metadata) so local playback can never be
    /// attributed to — or write history under — the previously loaded video.
    public func playLocalFile(_ url: URL, title: String? = nil, artist: String? = nil) {
        generation += 1
        currentStream = nil
        currentVideoID = nil
        lastResolvedMedia = nil
        nowPlayingTitle = title
        nowPlayingArtist = artist
        let item = AVPlayerItem(url: url)
        playerItem = item
        observe(item: item)
        player.replaceCurrentItem(with: item)
        state = PlaybackState(status: .loading)
        resetWaiting()
        startProgressObserver()
        player.play()
        notifyNowPlayingChanged()
    }

    public func stop() {
        generation += 1
        itemObservation?.invalidate()
        timeControlObservation?.invalidate()
        stopProgressObserver()
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        currentStream = nil
        currentVideoID = nil
        // Nil it so an expired stream URL cannot be replayed later by the
        // quality picker after playback has been torn down.
        lastResolvedMedia = nil
        state = PlaybackState(status: .idle)
        resetWaiting()
        notifyNowPlayingChanged()
    }

    private func startProgressObserver() {
        stopProgressObserver()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                guard let self else { return }
                self.onProgress?(seconds)
                self.notifyNowPlayingChanged()
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
        // Bind deliveries to this exact item identity (Sendable token): late
        // callbacks from a replaced item must never mark a healthy successor
        // failed or ready.
        let observedItemID = ObjectIdentifier(item)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            // Extract the Sendable status before hopping actors; capturing the
            // non-Sendable AVPlayerItem across a Task boundary is illegal on
            // Swift 6.0 toolchains.
            let status = observed.status
            Task { @MainActor in
                guard let currentItem = self?.player.currentItem,
                      ObjectIdentifier(currentItem) == observedItemID else { return }
                self?.handle(itemStatus: status)
            }
        }

        timeControlObservation?.invalidate()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let status = observed.timeControlStatus
            Task { @MainActor in
                self?.handle(timeControlStatus: status)
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
        notifyNowPlayingChanged()
    }

    private func handle(timeControlStatus: AVPlayer.TimeControlStatus) {
        switch timeControlStatus {
        case .playing:
            resetWaiting()
            if state.status == .ready {
                try? state.transition(to: .playing)
            }
        case .paused:
            resetWaiting()
            if state.status == .playing {
                try? state.transition(to: .paused)
            }
        case .waitingToPlayAtSpecifiedRate:
            // Buffering right after ready is normal; only a sustained wait
            // (no `playing` transition within the stall timeout) is a stall.
            // A generation-bound watchdog fires even if no further KVO
            // callback arrives, so the check does not depend on more traffic.
            if state.status == .ready, stallWatchdog == nil {
                let gen = generation
                let timeout = stallTimeout
                stallWatchdog = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    await self?.checkForStall(generation: gen)
                }
            }
        @unknown default:
            break
        }
        notifyNowPlayingChanged()
    }

    /// Watchdog body: fails playback as `.stalled` only if this generation is
    /// still current and the player is still waiting after `.ready`.
    private func checkForStall(generation gen: Int) {
        guard gen == generation else { return }
        guard state.status == .ready,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
        stallWatchdog = nil
        state = PlaybackState(status: .failed, error: .stalled)
        notifyNowPlayingChanged()
    }

    /// Cancels any pending stall watchdog and clears waiting bookkeeping;
    /// called on every non-waiting transition and every selection change so a
    /// stale timestamp can never trigger an instant false stall later.
    private func resetWaiting() {
        stallWatchdog?.cancel()
        stallWatchdog = nil
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
    public func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }
}
