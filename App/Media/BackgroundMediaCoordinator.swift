import AVFoundation
import MediaPlayer
import os

/// Coordinates background audio: configures `AVAudioSession`, publishes Now
/// Playing metadata, routes `MPRemoteCommandCenter` to the player, and observes
/// and handles audio-session interruptions. Device-only behaviors (real
/// background suspension, lock-screen remotes, PiP on device) are deferred to
/// G10; the command/interruption mapping and metadata content are
/// deterministically tested.
@MainActor
public final class BackgroundMediaCoordinator {
    private let target: PlayerCommandTarget
    /// Tokens returned by `addTarget` for the commands this coordinator itself
    /// registered; non-nil while installed. Re-registration removes exactly
    /// these targets, never handlers owned by other components.
    private var playCommandToken: Any?
    private var pauseCommandToken: Any?
    private var togglePlayPauseCommandToken: Any?
    private var seekCommandToken: Any?
    /// Token for the installed audio-session interruption observer; non-nil
    /// while a subscription is active.
    private var interruptionObserver: NSObjectProtocol?
    /// Token for the installed audio-session route-change observer; non-nil
    /// while a subscription is active.
    private var routeChangeObserver: NSObjectProtocol?
    /// Whether the target was playing when the current interruption began;
    /// gates automatic resume on `.ended(shouldResume: true)` so an
    /// interruption that began during intentional pause stays paused.
    private var wasPlayingAtInterruptionBegan: Bool?
    /// Optional probe of the target's playing state, captured at interruption
    /// begin to gate auto-resume. When nil (deterministic mapping use), resume
    /// behavior is unchanged.
    public var isPlayingProvider: (@MainActor () -> Bool)?
    /// Observable outcome of the last `configureAudioSession()` attempt so UI
    /// and diagnostics can see silent `try?` failures.
    public private(set) var audioSessionState: AudioSessionState = .notConfigured

    public enum AudioSessionState: Equatable {
        case notConfigured
        case configured
        case failed(String)
    }

    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "background-media")

    public init(target: PlayerCommandTarget) {
        self.target = target
    }

    public enum RemoteCommand {
        case play
        case pause
        case togglePlayPause
        case seek(TimeInterval)
    }

    public enum Interruption: Sendable {
        case began
        case ended(shouldResume: Bool)
    }

    // MARK: - Deterministic mapping

    public func handleRemoteCommand(_ command: RemoteCommand) {
        switch command {
        case .play: target.play()
        case .pause: target.pause()
        case .togglePlayPause: target.togglePlayPause()
        case .seek(let seconds): target.seek(to: seconds)
        }
    }

    public func handleInterruption(_ interruption: Interruption) {
        switch interruption {
        case .began:
            wasPlayingAtInterruptionBegan = isPlayingProvider?()
            target.pause()
        case .ended(let shouldResume):
            // Auto-resume only if the target was actually playing when the
            // interruption began; a pause the user chose stays paused.
            let shouldAutoResume: Bool
            if let wasPlaying = wasPlayingAtInterruptionBegan {
                shouldAutoResume = shouldResume && wasPlaying
            } else {
                shouldAutoResume = shouldResume
            }
            wasPlayingAtInterruptionBegan = nil
            if shouldAutoResume { target.play() }
        }
    }

    // MARK: - Live wiring (device/Simulator-runnable)

    public func configureAudioSession() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                BackgroundMediaPolicy.audioSessionCategory,
                mode: BackgroundMediaPolicy.audioSessionMode,
                options: BackgroundMediaPolicy.audioSessionOptions
            )
            try session.setActive(true)
            audioSessionState = .configured
        } catch {
            audioSessionState = .failed(String(describing: error))
            Self.logger.fault("Audio session configuration failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Remove only the targets this coordinator previously installed, keeping
        // repeated registrations (view re-appearance) from stacking duplicates
        // without detaching handlers other components own on the shared center.
        if let token = playCommandToken { center.playCommand.removeTarget(token) }
        if let token = pauseCommandToken { center.pauseCommand.removeTarget(token) }
        if let token = togglePlayPauseCommandToken {
            center.togglePlayPauseCommand.removeTarget(token)
        }
        // MPRemoteCommandCenter has no seek command; lock-screen/Bluetooth
        // seeking arrives through changePlaybackPositionCommand.
        if let token = seekCommandToken { center.changePlaybackPositionCommand.removeTarget(token) }
        playCommandToken = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.play) }
            return .success
        }
        pauseCommandToken = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.pause) }
            return .success
        }
        togglePlayPauseCommandToken = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.togglePlayPause) }
            return .success
        }
        seekCommandToken = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let seconds = positionEvent.positionTime
            Task { @MainActor in self?.handleRemoteCommand(.seek(seconds)) }
            return .success
        }
    }

    /// Subscribes to real `AVAudioSession` route changes; remove-before-add
    /// keeps repeated registrations from stacking duplicate observers,
    /// mirroring `registerInterruptionObservation()`. Unplugging the current
    /// output device pauses playback instead of blaring from speakers.
    public func registerRouteChangeObservation() {
        if let token = routeChangeObserver {
            NotificationCenter.default.removeObserver(token)
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable values before hopping actors.
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(rawReason: reasonValue)
            }
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        switch reason {
        case .oldDeviceUnavailable:
            target.pause()
        default:
            Self.logger.info("Audio route changed: \(reason.rawValue, privacy: .public)")
        }
    }

    /// Subscribes to real `AVAudioSession` interruptions and forwards them to
    /// `handleInterruption(_:)` on the main actor. Remove-before-add keeps
    /// repeated registrations (view re-appearance) from stacking duplicate
    /// observers, mirroring `registerRemoteCommands()`.
    public func registerInterruptionObservation() {
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the Sendable mapping before hopping actors; carrying the
            // non-Sendable Notification across a Task boundary is illegal on
            // Swift 6.0 toolchains.
            guard let interruption = BackgroundMediaCoordinator.interruption(from: notification) else { return }
            Task { @MainActor [weak self] in
                self?.handleInterruption(interruption)
            }
        }
    }

    /// Pure userInfo → `Interruption` mapping; nil for unrecognized payloads.
    private nonisolated static func interruption(from notification: Notification) -> Interruption? {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return nil }
        switch type {
        case .began:
            return .began
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            return .ended(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    public func updateNowPlaying(_ info: [String: Any]) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Publishes lock-screen metadata from the player's snapshot. An inactive
    /// snapshot (nothing loaded, nothing playing) clears the entry so a stale
    /// title never lingers after playback stops.
    public func publishNowPlaying(snapshot: NowPlayingSnapshot) {
        guard snapshot.isActive else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        updateNowPlaying(NowPlayingInfoBuilder.info(
            title: snapshot.title,
            artist: snapshot.artist,
            duration: snapshot.duration,
            currentTime: snapshot.currentTime,
            rate: snapshot.rate
        ))
    }
}
