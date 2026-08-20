import Foundation

/// Normalized, YouTube-Data-API-derived video summary. Durations are known
/// before short-form eligibility decisions so `ShortFormPolicy` can filter
/// without extra round-trips.
public struct VideoSummary: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let channelTitle: String
    public let durationSeconds: Int?
    public let publishedAt: Date?
    public let thumbnailURL: URL?
    public let description: String?

    public init(
        id: String,
        title: String,
        channelTitle: String,
        durationSeconds: Int?,
        publishedAt: Date?,
        thumbnailURL: URL?,
        description: String?
    ) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.durationSeconds = durationSeconds
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.description = description
    }

    /// Best-effort duration parse from an ISO-8601 `PT#M#S` contentDetails
    /// string. Kept here so UI never depends on raw API shape.
    public static func duration(from iso: String) -> Int? {
        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) else { return nil }
        let h = rangeInt(iso, match, at: 1)
        let m = rangeInt(iso, match, at: 2)
        let s = rangeInt(iso, match, at: 3)
        let total = (h ?? 0) * 3600 + (m ?? 0) * 60 + (s ?? 0)
        return total > 0 ? total : nil
    }

    private static func rangeInt(_ string: String, _ match: NSTextCheckingResult, at index: Int) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return Int(string[swiftRange])
    }
}
