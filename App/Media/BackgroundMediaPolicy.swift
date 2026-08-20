import AVFoundation

/// Deterministic background-media session policy. The real `AVAudioSession`
/// activation happens in `BackgroundMediaCoordinator`; this pure surface is
/// what makes the capability choice testable.
public enum BackgroundMediaPolicy {
    public static var audioSessionCategory: AVAudioSession.Category { .playback }
    public static var audioSessionMode: AVAudioSession.Mode { .moviePlayback }
    public static var audioSessionOptions: AVAudioSession.CategoryOptions { [] }
}
