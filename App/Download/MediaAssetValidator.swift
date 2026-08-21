import AVFoundation

/// Errors surfaced by the native asset validator; the coordinator maps any of
/// them to `.validationFailed`.
enum MediaAssetValidationError: Error {
    case missingVideoTrack
    case missingAudioTrack
}

/// Native AVFoundation deep validation for finalized media files. Deeper than
/// the coordinator's existence+size floor: a truncated-but-nonempty file that
/// AVFoundation cannot load as a playable asset is discarded instead of being
/// registered as an offline download. Public because it appears in a default
/// argument of DownloadManager's public initializer (default values are
/// evaluated at the call site).
public enum MediaAssetValidator {
    /// Builds the `@Sendable` seam handed to `DownloadCoordinator`; every
    /// download tier carries both a video and an audio track.
    public static func makeSeam() -> (@Sendable (URL) async throws -> Void) {
        { url in
            let asset = AVURLAsset(url: url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if videoTracks.isEmpty {
                throw MediaAssetValidationError.missingVideoTrack
            }
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if audioTracks.isEmpty {
                throw MediaAssetValidationError.missingAudioTrack
            }
        }
    }
}
