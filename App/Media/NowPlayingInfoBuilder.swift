import MediaPlayer

/// Pure builder for the Now Playing info dictionary. Kept side-effect free so
/// the metadata content is deterministically testable without `MPNowPlayingInfoCenter`.
public enum NowPlayingInfoBuilder {
    public static func info(
        title: String?,
        artist: String?,
        duration: TimeInterval,
        currentTime: TimeInterval,
        artwork: Data? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "",
            MPMediaItemPropertyArtist: artist ?? "",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        if let artwork {
            dict[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(data: artwork)
        }
        return dict
    }
}
