import SwiftUI

/// Reusable long-form video card (DDV2-06): thumbnail with duration badge,
/// title, channel, relative publish date, and an optional continue-watching
/// progress strip fed from LOCAL history. No engagement metrics, no autoplay.
struct VideoCard: View {
    let video: VideoSummary
    /// 0...1 resume position from local history; nil = never started.
    var progressFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(video.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let published = Self.relativePublished(video.publishedAt) {
                    Text(published)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        // Natural child elements stay exposed: journeys and VoiceOver read
        // the real title/channel texts. No accessibilityElement override.
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if video.thumbnailURL == nil {
                    // HB-029: a missing legacy thumbnail URL must reach a
                    // bounded failure glyph, not spin forever (AsyncImage
                    // never leaves .empty for a nil URL).
                    failedThumbnail
                } else {
                    AsyncImage(url: video.thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                // Graceful degradation is handled by the failure
                                // branch; a loaded image simply fills the slot.
                        case .failure:
                            failedThumbnail
                        default:
                            loadingThumbnail
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge = Self.durationText(video.durationSeconds) {
                    Text(badge)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if let fraction = progressFraction, fraction > 0, fraction < 1 {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.35))
                            Rectangle()
                                .fill(.red)
                                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                        }
                    }
                    .frame(height: 4)
                }
            }
            // HB-028: VoiceOver users hear how much of the video they have
            // already watched. Natural-child label composition stays intact —
            // this only ADDS a value on the card container.
            .accessibilityElement(children: .contain)
            .accessibilityValue(
                progressFraction.map { "\(Int(($0 * 100).rounded()))% watched" } ?? ""
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var loadingThumbnail: some View {
        ZStack {
            Rectangle().fill(.gray.opacity(0.18))
            ProgressView()
        }
    }

    private var failedThumbnail: some View {
        ZStack {
            Rectangle().fill(.gray.opacity(0.18))
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Copy helpers

    /// Deterministic H:MM:SS / M:SS duration badge; nil hides the badge.
    static func durationText(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Cached relative-date formatter (HB-027): constructing one per card per
    /// render was pure churn. MainActor-isolated because only view bodies call
    /// this and RelativeDateTimeFormatter is not Sendable.
    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()

    @MainActor
    static func relativePublished(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func accessibilityLabel(for video: VideoSummary) -> String {
        var parts = [video.title, video.channelTitle]
        if let duration = durationText(video.durationSeconds) {
            parts.append("Duration \(duration)")
        }
        return parts.compactMap { $0.isEmpty ? nil : $0 }.joined(separator: ", ")
    }
}
