import Foundation

public enum StreamKind: String, Codable, Sendable, Hashable {
    case combined
    case videoOnly
    case audioOnly
}

public struct MediaStream: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let videoID: String
    public let resolution: Int?
    public let kind: StreamKind
    public let nativePlayable: Bool
    public let container: String?
    public let videoCodec: String?
    public let audioCodec: String?
    public let sourceURL: URL
    public let expiresAt: Date?

    public init(
        id: String,
        videoID: String,
        resolution: Int?,
        kind: StreamKind,
        nativePlayable: Bool,
        container: String?,
        videoCodec: String?,
        audioCodec: String?,
        sourceURL: URL,
        expiresAt: Date?
    ) {
        self.id = id
        self.videoID = videoID
        self.resolution = resolution
        self.kind = kind
        self.nativePlayable = nativePlayable
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.sourceURL = sourceURL
        self.expiresAt = expiresAt
    }
}

public struct ResolvedMedia: Codable, Sendable, Hashable {
    public let videoID: String
    public let extractedAt: Date
    public let combined: [MediaStream]
    public let videoOnly: [MediaStream]
    public let audioOnly: [MediaStream]

    public init(
        videoID: String,
        extractedAt: Date,
        combined: [MediaStream],
        videoOnly: [MediaStream],
        audioOnly: [MediaStream]
    ) {
        self.videoID = videoID
        self.extractedAt = extractedAt
        self.combined = combined
        self.videoOnly = videoOnly
        self.audioOnly = audioOnly
    }
}
