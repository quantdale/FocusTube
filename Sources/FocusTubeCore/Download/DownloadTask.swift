import Foundation

/// A single stream that must be fetched to produce one download. A combined
/// download has one component; an adaptive (video+audio) download has two.
public struct DownloadComponent: Sendable, Hashable, Codable {
    public let streamID: String
    public let sourceURL: URL

    public init(streamID: String, sourceURL: URL) {
        self.streamID = streamID
        self.sourceURL = sourceURL
    }
}

/// A single download job tracked by the coordinator.
public struct DownloadTask: Identifiable, Sendable, Hashable {
    public let id: String
    public let videoID: String
    public let resolution: Int
    public let destinationURL: URL
    public let components: [DownloadComponent]
    public private(set) var state: DownloadState

    public init(
        id: String,
        videoID: String,
        streamID: String,
        resolution: Int,
        sourceURL: URL,
        destinationURL: URL,
        state: DownloadState = DownloadState()
    ) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.destinationURL = destinationURL
        self.components = [DownloadComponent(streamID: streamID, sourceURL: sourceURL)]
        self.state = state
    }

    public init(
        id: String,
        videoID: String,
        resolution: Int,
        destinationURL: URL,
        components: [DownloadComponent],
        state: DownloadState = DownloadState()
    ) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.destinationURL = destinationURL
        self.components = components
        self.state = state
    }

    /// Convenience accessor for single-component (combined) downloads.
    public var streamID: String? { components.first?.streamID }
    public var sourceURL: URL? { components.first?.sourceURL }

    public mutating func apply(_ state: DownloadState) {
        self.state = state
    }

    /// Applies a validated state-machine transition to the task's state.
    /// Exposed so callers outside this file never need direct setter access.
    public mutating func transition(to status: DownloadStatus) throws(DownloadState.TransitionError) {
        try state.transition(to: status)
    }
}

/// Input used to enqueue a new download. May carry one component (combined
/// stream) or two (adaptive video + audio).
public struct DownloadRequest: Sendable {
    public let id: String
    public let videoID: String
    public let resolution: Int
    public let destinationURL: URL
    public let components: [DownloadComponent]

    /// Video IDs arrive from API JSON and are later embedded in filesystem
    /// path components (`<mediaDirectory>/<videoID>/<quality>/media.mp4`).
    /// Only YouTube's base64url ID alphabet, bounded to 1–64 characters, is
    /// accepted; anything else could traverse paths or smuggle separators.
    public static func isValidVideoID(_ videoID: String) -> Bool {
        guard !videoID.isEmpty, videoID.count <= 64 else { return false }
        return videoID.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    public init(
        id: String,
        videoID: String,
        streamID: String,
        resolution: Int,
        sourceURL: URL,
        destinationURL: URL
    ) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.destinationURL = destinationURL
        self.components = [DownloadComponent(streamID: streamID, sourceURL: sourceURL)]
    }

    public init(
        id: String,
        videoID: String,
        resolution: Int,
        destinationURL: URL,
        components: [DownloadComponent]
    ) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.destinationURL = destinationURL
        self.components = components
    }
}
