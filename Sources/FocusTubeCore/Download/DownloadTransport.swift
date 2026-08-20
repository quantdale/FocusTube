import Foundation

/// Outcome reported by a `DownloadTransport` back to the coordinator.
public enum DownloadEvent: Sendable {
    case progress(bytes: Int64, total: Int64)
    case completed(tempLocation: URL)
    case failed(DownloadError)
}

/// Abstraction over the actual byte transport (URLSession background in the app,
/// a fake in tests). Keeps the deterministic download state machine free of
/// networking and filesystem specifics.
public protocol DownloadTransport: Sendable {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async
    func cancel(taskID: String) async
}

/// Filesystem seam so finalization/validation are deterministic in tests.
public protocol FileManaging: Sendable {
    func fileExists(at url: URL) -> Bool
    func size(of url: URL) -> Int64
    func createDirectory(at url: URL) throws
    func replaceItem(at destination: URL, withItemAt item: URL) throws
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
}
