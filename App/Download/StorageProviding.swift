import Foundation
import os

/// Abstraction over available storage so download admission is deterministically
/// testable without real volume queries.
public protocol StorageProviding: Sendable {
    func availableCapacity(for url: URL) -> Int64
}

public struct VolumeStorage: StorageProviding {
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "storage")

    public init() {}

    /// Reports 0 on a failed query so admission refuses conservatively; the
    /// failure itself is logged so a persistently blocked download is diagnosable.
    public func availableCapacity(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else {
            Self.logger.error("Volume capacity query failed (\(url.path, privacy: .private)); refusing conservatively with 0")
            return 0
        }
        return Int64(capacity)
    }
}
