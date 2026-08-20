public enum MediaStreamFilter {
    public static let allowedResolutions: Set<Int> = [1080, 720, 480, 360]

    /// Retains only streams whose resolution is in the hard allowed set.
    /// Audio-only streams are always retained because adaptive muxing needs them.
    public static func allowed(_ streams: [MediaStream], allowed resolutions: Set<Int> = allowedResolutions) -> [MediaStream] {
        streams.filter { stream in
            switch stream.kind {
            case .audioOnly:
                return true
            case .combined, .videoOnly:
                guard let resolution = stream.resolution else { return false }
                return resolutions.contains(resolution)
            }
        }
    }

    /// Online playback selection: prefer a native-playable combined stream at the
    /// highest allowed resolution. Never returns a stream above 1080p.
    public static func selectOnlineStream(_ media: ResolvedMedia, allowed resolutions: Set<Int> = allowedResolutions) -> MediaStream? {
        let candidates = allowed(media.combined, allowed: resolutions).filter { $0.nativePlayable }
        return candidates.max { ($0.resolution ?? 0) < ($1.resolution ?? 0) }
    }

    /// Returns a copy with only allowed-resolution streams retained.
    public static func filter(_ media: ResolvedMedia, allowed resolutions: Set<Int> = allowedResolutions) -> ResolvedMedia {
        ResolvedMedia(
            videoID: media.videoID,
            extractedAt: media.extractedAt,
            combined: allowed(media.combined, allowed: resolutions),
            videoOnly: allowed(media.videoOnly, allowed: resolutions),
            audioOnly: media.audioOnly
        )
    }
}
