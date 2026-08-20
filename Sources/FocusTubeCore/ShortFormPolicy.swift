public struct ShortFormPolicy: Sendable {
    public static let maximumAllowedShortFormDurationSeconds = 180

    public init() {}

    /// Conservative FocusTube policy: videos at or below 180 seconds are hidden
    /// from long-form discovery surfaces. This intentionally favors false positives
    /// over accidentally recreating short-form consumption behavior.
    public func isBlocked(durationSeconds: Int) -> Bool {
        durationSeconds <= Self.maximumAllowedShortFormDurationSeconds
    }

    public func isBlocked(urlPath: String) -> Bool {
        urlPath.lowercased().contains("/shorts/")
    }
}
