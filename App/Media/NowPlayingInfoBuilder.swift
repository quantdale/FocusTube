import MediaPlayer
import UIKit

/// Pure builder for the Now Playing info dictionary. Kept side-effect free so
/// the metadata content is deterministically testable without `MPNowPlayingInfoCenter`.
public enum NowPlayingInfoBuilder {
    public static func info(
        title: String?,
        artist: String?,
        duration: TimeInterval,
        currentTime: TimeInterval,
        artwork: Data? = nil,
        rate: Double = 1.0
    ) -> [String: Any] {
        var dict: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "",
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]
        if let artwork, let image = UIImage(data: artwork) {
            dict[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
        }
        return dict
    }
}

/// Immutable playback snapshot published to the lock screen. Built by the
/// player coordinator (which owns the AVPlayer) and consumed by the background
/// media coordinator, so neither side needs to reach into the other's state.
public struct NowPlayingSnapshot: Sendable {
    public var title: String?
    public var artist: String?
    public var duration: TimeInterval
    public var currentTime: TimeInterval
    /// Actual playback rate (0 while paused); lock screens use it to animate
    /// the elapsed time correctly.
    public var rate: Double

    /// False once nothing is loaded and nothing plays; publishers clear the
    /// Now Playing info instead of leaving a stale lock-screen entry.
    public var isActive: Bool {
        duration > 0 || currentTime > 0 || rate != 0
    }

    public init(
        title: String?,
        artist: String?,
        duration: TimeInterval,
        currentTime: TimeInterval,
        rate: Double
    ) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.currentTime = currentTime
        self.rate = rate
    }
}
