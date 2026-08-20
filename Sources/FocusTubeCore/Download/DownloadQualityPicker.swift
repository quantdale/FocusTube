import Foundation

/// Resolves the actually available download qualities (a subset of
/// 1080/720/480/360) from resolved media. Never fabricates a quality that the
/// source did not provide.
public struct DownloadQualityPicker {
    public init() {}

    public func availableQualities(from media: ResolvedMedia) -> [DownloadQuality] {
        let resolutions = (media.combined + media.videoOnly).compactMap { $0.resolution }
        let set = Set(resolutions)
        return DownloadQuality.descending.filter { set.contains($0.rawValue) }
    }

    public func isAvailable(_ quality: DownloadQuality, from media: ResolvedMedia) -> Bool {
        availableQualities(from: media).contains(quality)
    }
}
