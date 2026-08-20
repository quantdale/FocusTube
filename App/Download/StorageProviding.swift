import Foundation

/// Abstraction over available storage so download admission is deterministically
/// testable without real volume queries.
public protocol StorageProviding: Sendable {
    func availableCapacity(for url: URL) -> Int64
}

public struct VolumeStorage: StorageProviding {
    public init() {}

    public func availableCapacity(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}
