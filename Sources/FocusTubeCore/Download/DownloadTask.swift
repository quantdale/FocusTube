import Foundation

/// A single download job tracked by the coordinator.
public struct DownloadTask: Identifiable, Sendable, Hashable {
    public let id: String
    public let videoID: String
    public let streamID: String
    public let resolution: Int
    public let sourceURL: URL
    public let destinationURL: URL
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
        self.streamID = streamID
        self.resolution = resolution
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.state = state
    }

    public mutating func apply(_ state: DownloadState) {
        self.state = state
    }
}

/// Input used to enqueue a new download.
public struct DownloadRequest: Sendable {
    public let id: String
    public let videoID: String
    public let streamID: String
    public let resolution: Int
    public let sourceURL: URL
    public let destinationURL: URL

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
        self.streamID = streamID
        self.resolution = resolution
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}
