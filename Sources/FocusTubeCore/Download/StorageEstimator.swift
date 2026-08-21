import Foundation

/// Conservative free-space admission estimates for download jobs. `MediaStream`
/// exposes no byte sizes today, so the estimate combines per-tier nominal
/// bitrates with the known duration plus margin. Adaptive jobs need extra
/// transient headroom because both components and the muxed output coexist on
/// disk simultaneously (docs/03: refuse safely before consuming device storage).
public enum StorageEstimator {
    /// Nominal total bitrate (video+audio) per quality tier, bits per second.
    private static func nominalBitrate(resolution: Int) -> Int64 {
        switch resolution {
        case 1080: return 5_200_000
        case 720: return 2_700_000
        case 480: return 1_200_000
        case 360: return 900_000
        default: return 2_700_000
        }
    }

    /// Estimated bytes required on disk for the transfer, or 0 when the
    /// duration is unknown (no up-front admission refusal can then be made).
    public static func requiredBytes(
        resolution: Int,
        durationSeconds: TimeInterval,
        componentCount: Int
    ) -> Int64 {
        guard durationSeconds > 0 else { return 0 }
        let mediaBytes = Int64(
            (Double(nominalBitrate(resolution: resolution) / 8) * durationSeconds.rounded(.up))
                .rounded(.up)
        )
        // Adaptive: components (~1x) + muxed final (~1x) coexist; both paths
        // carry a 25% container/overhead margin.
        let occupancyMultiplier: Int64 = componentCount > 1 ? 3 : 1
        return mediaBytes * occupancyMultiplier + mediaBytes / 4
    }
}
