import Foundation
import YouTubeKit
import FocusTubeCore

public struct YouTubeKitMediaExtractor: MediaExtracting {
    public init() {}

    public func resolve(videoID: String) async throws -> ResolvedMedia {
        let youtube = YouTube(videoID: videoID, methods: [.local])

        let streams: [YouTubeKit.Stream]
        do {
            streams = try await youtube.streams
        } catch {
            throw mapError(error)
        }

        let combined = streams.filter { $0.includesVideoAndAudioTrack }
            .map { map($0, videoID: videoID) }
        let videoOnly = streams.filter { $0.includesVideoTrack && !$0.includesAudioTrack }
            .map { map($0, videoID: videoID) }
        let audioOnly = streams.filter { $0.includesAudioTrack && !$0.includesVideoTrack }
            .map { map($0, videoID: videoID) }

        let raw = ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: combined,
            videoOnly: videoOnly,
            audioOnly: audioOnly
        )

        return MediaStreamFilter.filter(raw)
    }

    private func map(_ stream: YouTubeKit.Stream, videoID: String) -> MediaStream {
        let kind: StreamKind = stream.includesVideoAndAudioTrack
            ? .combined
            : (stream.includesVideoTrack ? .videoOnly : .audioOnly)

        return MediaStream(
            id: stream.url.absoluteString,
            videoID: videoID,
            resolution: stream.videoResolution,
            kind: kind,
            nativePlayable: stream.isNativelyPlayable,
            container: String(describing: stream.fileExtension),
            videoCodec: stream.videoCodec.map { String(describing: $0) },
            audioCodec: stream.audioCodec.map { String(describing: $0) },
            sourceURL: stream.url,
            expiresAt: nil
        )
    }

    private func mapError(_ error: Error) -> ExtractionError {
        if let ytError = error as? YouTubeKitError {
            switch ytError {
            case .videoUnavailable, .videoPrivate, .videoAgeRestricted, .membersOnly:
                return .unavailable
            case .extractError, .liveStreamError:
                return .extractorIncompatible
            default:
                return .unknown
            }
        }

        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return .transientNetwork
        }
        return .unknown
    }
}
