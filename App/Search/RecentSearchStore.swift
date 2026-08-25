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
    /// Injected persistence boundary (H3-03/HB-025) for deterministic
    /// failure-injection tests.
    private let performSave: () throws -> Void
    /// HB-025 truthful signal: set when persistence fails; cleared by the next
    /// successful persist. Entries only ever reflect durable truth while the
    /// flag is set (write-through ordering below).
    public private(set) var isPersistenceDegraded = false

    public init(context: ModelContext, saveHandler: (() throws -> Void)? = nil) {
        self.context = context
        self.performSave = saveHandler ?? { try context.save() }
        load()
    }

    /// Records a query on explicit submit (policy handles dedupe/bound).
    /// Write-through: the in-memory view commits ONLY after persistence
    /// succeeds, so recents never claim more durability than the store holds.
    public func record(_ rawQuery: String) {
        let updated = SearchRecentsPolicy.record(entries, newQuery: rawQuery, now: Date())
        guard persist(updated) else { return }
        entries = updated
    }

    public func remove(_ query: String) {
        let updated = SearchRecentsPolicy.remove(query, from: entries)
        guard persist(updated) else { return }
        entries = updated
    }

    public func clear() {
        guard persist([]) else { return }
        entries.removeAll()
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
    /// Returns success so callers can gate their in-memory commit (HB-025).
    @discardableResult
    private func persist(_ updated: [RecentQueryEntry]) -> Bool {
        do {
            try context.delete(model: RecentSearchEntry.self)
            for entry in updated {
                context.insert(RecentSearchEntry(query: entry.query, updatedAt: entry.updatedAt))
            }
            try performSave()
            isPersistenceDegraded = false
            return true
        } catch {
            // A failed full-rewrite can leave deleted/inserted rows pending in
            // the context; roll them back so a later unrelated save cannot
            // resurrect this broken transaction.
            context.rollback()
            isPersistenceDegraded = true
            Self.logger.fault("Recent-search persist failed (\(error.localizedDescription)); keeping previous durable view")
            return false
        }
    }
}
