import Foundation

/// Platform-independent playback engine boundary (ADR-0007).
///
/// The production engine is the official YouTube IFrame Player hosted in a
/// WKWebView (iOS target). Core logic, tests and UI state depend only on this
/// protocol and on `IFramePlayerState`, never on WebKit.
@MainActor
public protocol PlayerEngine: AnyObject {
    /// Latest observed state. Engines publish changes via `onStateChange`.
    var state: IFramePlayerState { get }
    var onStateChange: (@MainActor (IFramePlayerState) -> Void)? { get set }

    func load(_ videoID: YouTubeVideoID, startSeconds: Double, autoplay: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func setPlaybackRate(_ rate: Double)
    func stop()
}

/// Commands the controller asks the embedded player to run. Rendering to
/// JavaScript lives here so it is unit-testable on Linux; the WebKit engine
/// only evaluates the returned string.
public enum IFramePlayerCommand: Equatable, Sendable {
    case load(YouTubeVideoID, startSeconds: Double)
    case cue(YouTubeVideoID, startSeconds: Double)
    case play
    case pause
    case seek(seconds: Double)
    case setPlaybackRate(Double)
    case stop

    /// JavaScript calling the documented IFrame Player API on the global `player`.
    public var javaScript: String {
        switch self {
        case let .load(id, start):
            return "player.loadVideoById({videoId:'\(id.rawValue)',startSeconds:\(Self.number(start))});"
        case let .cue(id, start):
            return "player.cueVideoById({videoId:'\(id.rawValue)',startSeconds:\(Self.number(start))});"
        case .play: return "player.playVideo();"
        case .pause: return "player.pauseVideo();"
        case let .seek(s): return "player.seekTo(\(Self.number(s)),true);"
        case let .setPlaybackRate(r): return "player.setPlaybackRate(\(Self.number(r)));"
        case .stop: return "player.stopVideo();"
        }
    }

    /// Finite, non-negative, locale-independent number literal.
    static func number(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
