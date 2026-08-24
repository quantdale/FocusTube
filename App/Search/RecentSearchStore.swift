import Foundation
import SwiftData
import os
import FocusTubeCore

/// Persisted deliberate recent-search query (DDV2-07). Additive SwiftData
/// entity — lightweight migration, never touches other stores.
@Model
final class RecentSearchEntry {
    @Attribute(.unique) var query: String
    var updatedAt: Date

    init(query: String, updatedAt: Date) {
        self.query = query
        self.updatedAt = updatedAt
    }
}

/// UI-facing store for recent searches. All ordering/dedupe/bound decisions
/// come from the pure `SearchRecentsPolicy`; this type only persists and
/// projects. Recording happens ONLY on explicit submit — typing alone never
/// mutates state and can never consume remote quota.
@MainActor
@Observable
public final class RecentSearchStore {
    /// Newest-first snapshot for the UI.
    public private(set) var entries: [RecentQueryEntry] = []

    private let context: ModelContext
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "search-recents")

    public init(context: ModelContext) {
        self.context = context
        load()
    }

    /// Records a query on explicit submit (policy handles dedupe/bound).
    public func record(_ rawQuery: String) {
        entries = SearchRecentsPolicy.record(entries, newQuery: rawQuery, now: Date())
        persist(entries)
    }

    public func remove(_ query: String) {
        entries = SearchRecentsPolicy.remove(query, from: entries)
        persist(entries)
    }

    public func clear() {
        entries.removeAll()
        persist(entries)
    }

    /// Local prefix/contains suggestions for the current typed fragment.
    public func suggestions(for typed: String) -> [RecentQueryEntry] {
        SearchRecentsPolicy.suggestions(for: typed, in: entries)
    }

    // MARK: - Persistence

    private func load() {
        do {
            var descriptor = FetchDescriptor<RecentSearchEntry>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            descriptor.fetchLimit = SearchRecentsPolicy.maxEntries + 5
            let rows = try context.fetch(descriptor)
            entries = rows.map { RecentQueryEntry(query: $0.query, updatedAt: $0.updatedAt) }
        } catch {
            Self.logger.fault("Recent-search fetch failed (\(error.localizedDescription)); starting empty")
            entries = []
        }
    }

    /// Rewrites the table from the policy-produced list. Personal-scale row
    /// counts make full-rewrite the simplest deterministic persistence.
    private func persist(_ updated: [RecentQueryEntry]) {
        do {
            try context.delete(model: RecentSearchEntry.self)
            for entry in updated {
                context.insert(RecentSearchEntry(query: entry.query, updatedAt: entry.updatedAt))
            }
            try context.save()
        } catch {
            Self.logger.fault("Recent-search persist failed (\(error.localizedDescription)); keeping in-memory view")
        }
    }
}
