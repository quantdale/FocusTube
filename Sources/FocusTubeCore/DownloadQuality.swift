public enum DownloadQuality: Int, CaseIterable, Codable, Sendable, Comparable, Hashable {
    case p360 = 360
    case p480 = 480
    case p720 = 720
    case p1080 = 1080

    public static func < (lhs: DownloadQuality, rhs: DownloadQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static var descending: [DownloadQuality] {
        allCases.sorted(by: >)
    }

    public static func highestAllowed(availableResolutions: some Sequence<Int>) -> DownloadQuality? {
        let available = Set(availableResolutions)
        return descending.first { available.contains($0.rawValue) }
    }
}
