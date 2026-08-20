import Foundation

/// Resolves the actually available download qualities (a subset of
/// 1080/720/480/360) from resolved media. Never fabricates a quality that the
/// source did not provide.
public struct DownloadQualityPicker {
    public init() {}

    public func availableQualities(from media: ResolvedMedia) -> [DownloadQuality] {
        DownloadQuality.descending.filter { quality in
            switch DownloadPlanner.plan(for: media, quality: quality) {
            case .unavailable:
                return false
            case .combined, .adaptive:
                return true
            }
        }
    }

    public func isAvailable(_ quality: DownloadQuality, from media: ResolvedMedia) -> Bool {
        availableQualities(from: media).contains(quality)
    }
}
