import AVFoundation
import MediaPlayer

/// Coordinates background audio: configures `AVAudioSession`, publishes Now
/// Playing metadata, routes `MPRemoteCommandCenter` to the player, and handles
/// interruptions. Device-only behaviors (real background suspension, lock-screen
/// remotes, PiP on device) are deferred to G10; the command/interruption mapping
/// and metadata content are deterministically tested.
@MainActor
public final class BackgroundMediaCoordinator {
    private let target: PlayerCommandTarget

    public init(target: PlayerCommandTarget) {
        self.target = target
    }

    public enum RemoteCommand {
        case play
        case pause
        case togglePlayPause
        case seek(TimeInterval)
    }

    public enum Interruption {
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
        center.playCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(.play)
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(.pause)
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteCommand(.togglePlayPause)
            return .success
        }
    }

    public func updateNowPlaying(_ info: [String: Any]) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
