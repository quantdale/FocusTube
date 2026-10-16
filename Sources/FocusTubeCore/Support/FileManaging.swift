import Foundation

/// Filesystem seam so LibraryStore file reconciliation is deterministic in tests.
public protocol FileManaging: Sendable {
    func fileExists(at url: URL) -> Bool
    func size(of url: URL) -> Int64
    func createDirectory(at url: URL) throws
    /// Atomically swaps an existing destination with a new item.
    /// Only valid when the destination already exists.
    func replaceItem(at destination: URL, withItemAt item: URL) throws
    /// Moves an item into place; used for first-time finalization where the
    /// destination does not exist yet and `replaceItem` would fail.
    func moveItem(at item: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
}

extension FileManager: FileManaging {
    public func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }

    public func size(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    public func createDirectory(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func replaceItem(at destination: URL, withItemAt item: URL) throws {
        _ = try replaceItemAt(destination, withItemAt: item, backupItemName: nil, options: [])
    }
    // moveItem(at:to:) is intentionally NOT redeclared here: Foundation already
    // provides it with the exact required signature, and a redeclaration would
    // shadow it (ambiguous call sites) and recurse into itself.
}
