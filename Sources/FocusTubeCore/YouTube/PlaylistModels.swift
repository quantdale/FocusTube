import Foundation

/// A user-owned YouTube playlist (bounded subset — FocusTube never rebuilds
/// the full official Library surface).
public struct PlaylistSummary: Sendable, Hashable {
    public let id: String
    public let title: String
    /// Privacy status raw value ("private"/"public"/"unlisted") when provided.
    public let privacyStatus: String?
    public let itemCount: Int

    public init(id: String, title: String, privacyStatus: String?, itemCount: Int) {
        self.id = id
        self.title = title
        self.privacyStatus = privacyStatus
        self.itemCount = itemCount
    }
}

/// One item inside a playlist. `playlistItemID` is the resource id needed to
/// REMOVE the item (playlistItems.delete); `videoID` is what plays.
/// H3-03 (HB-029): optional presentation fields let playlist-origin navigation
/// reconstruct a video page that keeps Subscribe actions and the description
/// instead of silently dropping them. Additive optionals with defaults —
/// older fakes/callers keep compiling.
public struct PlaylistItemSummary: Sendable, Hashable {
    public let playlistItemID: String
    public let videoID: String
    public let title: String
    public let channelTitle: String
    /// The VIDEO's own description when YouTube provides it here.
    public let videoDescription: String?
    public let thumbnailURL: String?
    /// The video owner's channel id, when provided (drives Subscribe state).
    public let channelID: String?

    public init(
        playlistItemID: String,
        videoID: String,
        title: String,
        channelTitle: String,
        videoDescription: String? = nil,
        thumbnailURL: String? = nil,
        channelID: String? = nil
    ) {
        self.playlistItemID = playlistItemID
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
        self.videoDescription = videoDescription
        self.thumbnailURL = thumbnailURL
        self.channelID = channelID
    }
}
