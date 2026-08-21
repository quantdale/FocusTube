import Foundation

/// Outcome reported by a `DownloadTransport` back to the coordinator. Multi-
/// component (adaptive) downloads report one event per component, tagged with
/// its index, so the coordinator can aggregate progress and finalize only once
/// every component has arrived.
public enum DownloadEvent: Sendable {
    case progress(component: Int, bytes: Int64, total: Int64)
    case completed(tempLocation: URL, component: Int)
    case failed(DownloadError)
}

/// A background transfer discovered alive in the process-independent session
/// after a relaunch, grouped by its originating request id.
public struct ReattachedDownload: Sendable, Equatable {
    public let requestID: String
    public let componentCount: Int

    public init(requestID: String, componentCount: Int) {
        self.requestID = requestID
        self.componentCount = componentCount
    }
}

/// Abstraction over the actual byte transport (real background URLSession in the
/// app, a fake in tests). Keeps the deterministic download state machine free of
/// networking and filesystem specifics. A single `DownloadRequest` may expand to
/// multiple underlying transfers (one per `DownloadComponent`).
public protocol DownloadTransport: Sendable {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async
    func cancel(taskID: String) async

    /// Re-registers event delivery for transfers that survived a previous
    /// process lifetime and reports the recovered request ids with their live
    /// component counts. Default: no transfers survive (in-process transports).
    func reattach(
        onEvent: @escaping @Sendable (_ requestID: String, _ event: DownloadEvent) -> Void
    ) async -> [ReattachedDownload]
}

extension DownloadTransport {
    public func reattach(
        onEvent: @escaping @Sendable (_ requestID: String, _ event: DownloadEvent) -> Void
    ) async -> [ReattachedDownload] {
        []
    }
}

/// Filesystem seam so finalization/validation are deterministic in tests.
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

    public func moveItem(at item: URL, to destination: URL) throws {
        try moveItem(at: item, to: destination)
    }
}
