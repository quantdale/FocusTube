import Foundation

/// A validated YouTube video id (11 chars of `[A-Za-z0-9_-]`).
/// Validation matters: the id is interpolated into JavaScript and an embed URL,
/// so anything else is rejected rather than escaped.
public struct YouTubeVideoID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.utf8.count == 11,
              raw.unicodeScalars.allSatisfy({ YouTubeVideoID.allowed.contains($0) })
        else { return nil }
        rawValue = raw
    }

    public var description: String { rawValue }

    private static let allowed: Set<Unicode.Scalar> = {
        var s = Set<Unicode.Scalar>()
        for c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".unicodeScalars { s.insert(c) }
        return s
    }()
}
