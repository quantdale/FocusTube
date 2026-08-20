import Foundation

/// Commands a background-media coordinator can issue against the active player.
public protocol PlayerCommandTarget {
    func play()
    func pause()
    func togglePlayPause()
    func seek(to seconds: TimeInterval)
}
