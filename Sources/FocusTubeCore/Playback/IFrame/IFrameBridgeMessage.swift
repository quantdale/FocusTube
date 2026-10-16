import Foundation

/// IFrame API `onStateChange` codes.
public enum YTPlayerStateCode: Int, Sendable, Equatable {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5
}

/// IFrame API `onError` codes.
public enum IFramePlayerError: Error, Equatable, Sendable {
    case invalidParameter          // 2
    case html5Error                // 5
    case videoNotFound             // 100
    case embeddingNotAllowed       // 101, 150
    case unknown(Int)

    public init(code: Int) {
        switch code {
        case 2: self = .invalidParameter
        case 5: self = .html5Error
        case 100: self = .videoNotFound
        case 101, 150: self = .embeddingNotAllowed
        default: self = .unknown(code)
        }
    }

    /// Whether retrying the same video can help.
    public var isRetryable: Bool { self == .html5Error }
}

/// A message posted by the embed page's JS (`window.webkit.messageHandlers.focustube.postMessage`).
/// Wire format: `{"event": "<name>", "data": <value>}`.
public enum IFrameBridgeMessage: Equatable, Sendable {
    case ready
    case stateChange(YTPlayerStateCode)
    case error(IFramePlayerError)
    case playbackRateChange(Double)
    case progress(currentTime: Double, duration: Double)

    public enum ParseError: Error, Equatable, Sendable {
        case notAnObject
        case missingEvent
        case unknownEvent(String)
        case invalidData(String)
    }

    /// Parse the body WebKit hands to a script message handler (already
    /// bridged to Foundation types: NSDictionary/NSNumber/NSString).
    public static func parse(_ body: Any) throws(ParseError) -> IFrameBridgeMessage {
        if let string = body as? String {
            guard let data = string.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data)
            else { throw .notAnObject }
            return try parse(obj)
        }
        guard let dict = body as? [String: Any] else { throw .notAnObject }
        guard let event = dict["event"] as? String else { throw .missingEvent }
        let payload = dict["data"]
        switch event {
        case "onReady":
            return .ready
        case "onStateChange":
            guard let code = int(payload), let state = YTPlayerStateCode(rawValue: code)
            else { throw .invalidData(event) }
            return .stateChange(state)
        case "onError":
            guard let code = int(payload) else { throw .invalidData(event) }
            return .error(IFramePlayerError(code: code))
        case "onPlaybackRateChange":
            guard let rate = double(payload), rate > 0 else { throw .invalidData(event) }
            return .playbackRateChange(rate)
        case "progress":
            guard let p = payload as? [String: Any],
                  let t = double(p["currentTime"]), let d = double(p["duration"]),
                  t >= 0, d >= 0
            else { throw .invalidData(event) }
            return .progress(currentTime: t, duration: d)
        default:
            throw .unknownEvent(event)
        }
    }

    private static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.rounded() == d { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func double(_ v: Any?) -> Double? {
        if let d = v as? Double, d.isFinite { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
}
