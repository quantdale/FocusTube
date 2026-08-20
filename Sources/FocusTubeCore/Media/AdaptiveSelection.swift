/// Adaptive (separate video/audio) component selection for native muxing.
///
/// Used when a combined stream is unavailable or when 1080p adaptive is
/// preferred. Never exceeds the 1080p ceiling; returns `nil` when a compliant
/// 1080p video-only component or an audio-only component is missing, in which
/// case the caller falls back to the combined path.
public enum AdaptiveSelection {
    /// Selects a 1080p native-playable video-only stream plus the first
    /// audio-only stream. Returns `nil` if either required component is absent.
    public static func select1080(
        _ media: ResolvedMedia,
        allowed resolutions: Set<Int> = MediaStreamFilter.allowedResolutions
    ) -> (video: MediaStream, audio: MediaStream)? {
        let videoCandidates = MediaStreamFilter.allowed(media.videoOnly, allowed: resolutions)
            .filter { $0.nativePlayable && ($0.resolution ?? 0) <= 1080 }
        let video = videoCandidates
            .filter { $0.resolution == 1080 }
            .max { ($0.resolution ?? 0) < ($1.resolution ?? 0) }
            ?? videoCandidates.max { ($0.resolution ?? 0) < ($1.resolution ?? 0) }

        guard let video else { return nil }
        guard let audio = media.audioOnly.first else { return nil }

        return (video, audio)
    }
}
