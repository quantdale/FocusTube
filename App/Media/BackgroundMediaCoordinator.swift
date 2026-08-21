import AVFoundation
import MediaPlayer

/// Coordinates background audio: configures `AVAudioSession`, publishes Now
/// Playing metadata, routes `MPRemoteCommandCenter` to the player, and observes
/// and handles audio-session interruptions. Device-only behaviors (real
/// background suspension, lock-screen remotes, PiP on device) are deferred to
/// G10; the command/interruption mapping and metadata content are
/// deterministically tested.
@MainActor
public final class BackgroundMediaCoordinator {
    private let target: PlayerCommandTarget
    /// Token for the installed audio-session interruption observer; non-nil
    /// while a subscription is active.
    private var interruptionObserver: NSObjectProtocol?

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
            target.pause()
        case .ended(let shouldResume):
            if shouldResume { target.play() }
        }
    }

    // MARK: - Live wiring (device/Simulator-runnable)

    public func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            BackgroundMediaPolicy.audioSessionCategory,
            mode: BackgroundMediaPolicy.audioSessionMode,
            options: BackgroundMediaPolicy.audioSessionOptions
        )
        try session.setActive(true)
    }

    public func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Remove-before-add keeps repeated registrations (view re-appearance)
        // from stacking duplicate handlers on the shared command center.
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.play) }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.pause) }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.handleRemoteCommand(.togglePlayPause) }
            return .success
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
}
