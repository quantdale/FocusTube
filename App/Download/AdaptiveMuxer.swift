import Foundation
import AVFoundation
import FocusTubeCore

public enum MuxError: Error, Equatable, Sendable {
    case missingComponent
    case incompatible
    case exportFailed
}

/// Native AVFoundation mux of a separate video-only and audio-only component
/// into a single playable file. No FFmpeg / yt-dlp / remote fallback is used;
/// if the native path is incompatible, the caller records evidence and triggers
/// an ADR review rather than introducing an unauthorized tool.
@MainActor
public struct AdaptiveMuxer {
    public init() {}

    public func mux(videoURL: URL, audioURL: URL, outputURL: URL) async -> Result<URL, MuxError> {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        do {
            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
            guard let videoTrack = videoTracks.first else { return .failure(.missingComponent) }
            guard let audioTrack = audioTracks.first else { return .failure(.missingComponent) }

            let composition = AVMutableComposition()
            guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return .failure(.incompatible)
            }

            try compVideo.insertTimeRange(videoTrack.timeRange, of: videoTrack, at: .zero)
            try compAudio.insertTimeRange(audioTrack.timeRange, of: audioTrack, at: .zero)

            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                return .failure(.incompatible)
            }
            export.outputURL = outputURL
            export.outputFileType = .mp4

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { continuation.resume() }
            }

            switch export.status {
            case .completed:
                return .success(outputURL)
            default:
                return .failure(.exportFailed)
            }
        } catch {
            return .failure(.missingComponent)
        }
    }
}
