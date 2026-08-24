import Foundation

/// Neutral summary of one completed offline download. Mirrors the app-layer
/// persisted media entry so sorting/grouping/formatting policy stays
/// deterministic and Windows-testable.
public struct OfflineMediaSummary: Sendable, Hashable {
    public let id: String
    public let title: String
    public let channelTitle: String
    public let resolution: Int
    public let sizeBytes: Int64
    public let createdAt: Date

    public init(id: String, title: String, channelTitle: String, resolution: Int, sizeBytes: Int64, createdAt: Date) {
        self.id = id
        self.title = title
        self.channelTitle = channelTitle
        self.resolution = resolution
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}

/// Sort/group/format policy for the offline library (docs/07: sortable by
/// date/size/channel). Pure and deterministic.
public enum OfflineLibraryPolicy {
    public enum SortOrder: Sendable, Hashable {
        case newestFirst
        case largestFirst
        case byChannelThenNewest
    }

    /// Returns `items` ordered per `order`. Stable: ties preserve input order.
    public static func sorted(_ items: [OfflineMediaSummary], by order: SortOrder) -> [OfflineMediaSummary] {
        switch order {
        case .newestFirst:
            return items.sorted(by: { $0.createdAt > $1.createdAt })
        case .largestFirst:
            return items.sorted(by: { $0.sizeBytes > $1.sizeBytes })
        case .byChannelThenNewest:
            return items.sorted(by: { lhs, rhs in
                let comparison = lhs.channelTitle.caseInsensitiveCompare(rhs.channelTitle)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            })
        }
    }

    /// Groups items by channel title (case-insensitive), channels ordered by
    /// their newest item first; each group's items are newest-first.
    public static func groupedByChannel(_ items: [OfflineMediaSummary]) -> [(channel: String, items: [OfflineMediaSummary])] {
        var buckets: [String: [OfflineMediaSummary]] = [:]
        var keyByCanonical: [String: String] = [:]
        for item in items {
            let canonical = item.channelTitle.lowercased()
            if keyByCanonical[canonical] == nil {
                // Keep the FIRST-seen casing as the group display name.
                keyByCanonical[canonical] = item.channelTitle
            }
            buckets[canonical, default: []].append(item)
        }
        return buckets
            .map { key, group -> (channel: String, items: [OfflineMediaSummary]) in
                (keyByCanonical[key] ?? key, sorted(group, by: .newestFirst))
            }
            .sorted(by: { lhs, rhs in
                guard let l = lhs.items.map({ $0.createdAt }).max(),
                      let r = rhs.items.map({ $0.createdAt }).max() else {
                    return lhs.channel < rhs.channel
                }
                return l > r
            })
    }

    /// Total bytes across the offline library.
    public static func totalBytes(_ items: [OfflineMediaSummary]) -> Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Human-readable file size using binary units (Apple convention).
    /// Deterministic formatting — never locale-dependent output.
    public static func formattedFileSize(_ bytes: Int64) -> String {
        switch bytes {
        case ..<1_024:
            return "\(bytes) B"
        case ..<1_048_576:
            return "\(Self.oneDecimal(Double(bytes) / 1_024)) KB"
        case ..<1_073_741_824:
            return "\(Self.oneDecimal(Double(bytes) / 1_048_576)) MB"
        default:
            return "\(Self.oneDecimal(Double(bytes) / 1_073_741_824)) GB"
        }
    }

    private static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
