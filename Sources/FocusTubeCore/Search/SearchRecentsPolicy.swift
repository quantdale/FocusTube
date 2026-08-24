import Foundation

/// One persisted recent-search entry.
public struct RecentQueryEntry: Sendable, Hashable {
    public let query: String
    public let updatedAt: Date

    public init(query: String, updatedAt: Date) {
        self.query = query
        self.updatedAt = updatedAt
    }
}

/// Pure policy for deliberate recent searches (docs/07): deduplication is
/// case-insensitive, the most recent query leads, and history is hard-bounded
/// so it can never grow unbounded on device. No network involvement anywhere.
public enum SearchRecentsPolicy {
    public static let maxEntries = 10

    /// Returns the updated recents list after recording `newQuery`:
    /// trimmed, de-duplicated (case-insensitive), front-inserted, and
    /// clamped to `maxEntries`. Empty/whitespace queries are ignored
    /// (returns input unchanged).
    public static func record(_ current: [RecentQueryEntry], newQuery: String, now: Date, maxEntries: Int = SearchRecentsPolicy.maxEntries) -> [RecentQueryEntry] {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return current }
        var updated = current.filter {
            $0.query.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        updated.insert(RecentQueryEntry(query: trimmed, updatedAt: now), at: 0)
        guard updated.count > maxEntries else { return updated }
        return Array(updated.prefix(maxEntries))
    }

    /// Local suggestions for the typed prefix: entries whose query contains
    /// the (trimmed, case-insensitive) fragment, newest first. Never touches
    /// the network — typing alone cannot consume YouTube quota.
    public static func suggestions(for typed: String, in recents: [RecentQueryEntry]) -> [RecentQueryEntry] {
        let fragment = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return [] }
        return recents.filter {
            $0.query.localizedCaseInsensitiveContains(fragment)
        }
    }

    /// Removes one entry (by exact query match, case-insensitive).
    public static func remove(_ query: String, from recents: [RecentQueryEntry]) -> [RecentQueryEntry] {
        recents.filter { $0.query.caseInsensitiveCompare(query) != .orderedSame }
    }
}
