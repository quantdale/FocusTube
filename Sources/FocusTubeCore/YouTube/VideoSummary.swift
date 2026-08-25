import Foundation

/// Normalized, YouTube-Data-API-derived video summary. Durations are known
/// before short-form eligibility decisions so `ShortFormPolicy` can filter
/// without extra round-trips.
public struct VideoSummary: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let channelTitle: String
    /// Owning channel's resource ID when known (videos.list snippet).
    /// Additive optional: legacy persisted/decoded values degrade to nil and
    /// subscribe-state features simply stay unavailable for those rows.
    public let channelID: String?
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
        description: String?,
        channelID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.channelID = channelID
        self.durationSeconds = durationSeconds
        self.publishedAt = publishedAt
        self.thumbnailURL = thumbnailURL
        self.description = description
    }

    /// Best-effort duration parse from an ISO-8601 contentDetails string
    /// (`PT#H#M#S`, plus the week/day forms YouTube uses for long videos,
    /// e.g. `P1DT2H30M0S` and `P2W`). Anchored so partial prefixes cannot
    /// match; fractional seconds floor (never fabricates extra precision).
    /// Kept here so UI never depends on raw API shape.
    public static func duration(from iso: String) -> Int? {
        let pattern = #"^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) != nil else { return nil }
        func group(_ index: Int) -> Double? {
            guard let match = regex.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: iso) else { return nil }
            return Double(iso[swiftRange])
        }
        let weeks = group(1) ?? 0
        let days = group(2) ?? 0
        let h = group(3) ?? 0
        let m = group(4) ?? 0
        let s = group(5) ?? 0
        let total = weeks * 604_800 + days * 86_400 + h * 3600 + m * 60 + s
        let whole = Int(total)
        return whole > 0 ? whole : nil
    }
}
