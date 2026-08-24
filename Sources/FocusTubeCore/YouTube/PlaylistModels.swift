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
public struct PlaylistItemSummary: Sendable, Hashable {
    public let playlistItemID: String
    public let videoID: String
    public let title: String
    public let channelTitle: String

    public init(playlistItemID: String, videoID: String, title: String, channelTitle: String) {
        self.playlistItemID = playlistItemID
        self.videoID = videoID
        self.title = title
        self.channelTitle = channelTitle
    }
}
