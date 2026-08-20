import Foundation

/// Why a requested quality could not be turned into a download.
public enum DownloadUnavailableReason: Sendable, Equatable {
    case noAllowedStream
    case requestedQualityUnavailable
}

/// The concrete download strategy for a requested quality.
public enum DownloadPlan: Sendable, Equatable {
    /// A single combined (video+audio) stream at the requested resolution.
    case combined(DownloadComponent, resolution: Int)
    /// A separate video-only + audio-only pair at the requested resolution,
    /// to be muxed natively into one file.
    case adaptive(video: DownloadComponent, audio: DownloadComponent, resolution: Int)
    /// The requested quality cannot be produced exactly.
    case unavailable(reason: DownloadUnavailableReason)
}

/// Pure, deterministic selection of the exact download strategy for a requested
/// quality. The 1080p ceiling and exact-quality rule are enforced here:
///
/// - if a usable combined stream exists at exactly the requested resolution,
///   download it directly;
/// - else if an exact video-only stream at the requested resolution exists
///   together with any audio-only stream, download both and mux natively;
/// - otherwise the requested quality is reported unavailable — never silently
///   downgraded to a lower resolution.
public enum DownloadPlanner {
    public static func plan(
        for media: ResolvedMedia,
        quality: DownloadQuality
    ) -> DownloadPlan {
        let resolution = quality.rawValue

        let exactCombined = MediaStreamFilter.allowed(media.combined)
            .filter { $0.nativePlayable && $0.resolution == resolution }
            .first

        if let combined = exactCombined {
            return .combined(
                DownloadComponent(streamID: combined.id, sourceURL: combined.sourceURL),
                resolution: resolution
            )
        }

        let exactVideo = MediaStreamFilter.allowed(media.videoOnly)
            .filter { $0.nativePlayable && $0.resolution == resolution }
            .first

        if let video = exactVideo, let audio = media.audioOnly.first {
            return .adaptive(
                video: DownloadComponent(streamID: video.id, sourceURL: video.sourceURL),
                audio: DownloadComponent(streamID: audio.id, sourceURL: audio.sourceURL),
                resolution: resolution
            )
        }

        let hasAnyAllowed = !MediaStreamFilter.allowed(media.combined).isEmpty
            || !MediaStreamFilter.allowed(media.videoOnly).isEmpty
        return .unavailable(reason: hasAnyAllowed ? .requestedQualityUnavailable : .noAllowedStream)
    }
}
