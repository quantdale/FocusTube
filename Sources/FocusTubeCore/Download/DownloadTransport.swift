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
    /// Component indexes of the transfers that actually survived, parsed from
    /// durable per-task metadata so slots survive relaunch exactly.
    public let recoveredIndexes: [Int]

    public init(requestID: String, recoveredIndexes: [Int]) {
        self.requestID = requestID
        self.recoveredIndexes = recoveredIndexes
    }

    /// True when fewer components survived than the persisted record claims:
    /// the job can never finalize and must fail as interrupted instead of
    /// hanging in `.downloading` forever.
    public func isPartialRecovery(componentCount: Int) -> Bool {
        recoveredIndexes.count < componentCount
    }
}

/// Durable encoding of one underlying transfer's identity, written into the
/// transport task's description as `"<requestID>#<componentIndex>"`. Relaunch
/// reattachment decodes it to restore exact component slots instead of
/// guessing from enumeration order (which can swap an adaptive pair).
public enum DownloadTransferIdentity {
    public static func encode(requestID: String, componentIndex: Int) -> String {
        "\(requestID)#\(componentIndex)"
    }

    public static func decode(_ description: String?) -> (requestID: String, componentIndex: Int)? {
        guard let description, !description.isEmpty else { return nil }
        let parts = description.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty,
              let index = Int(parts[1]), index >= 0 else { return nil }
        return (String(parts[0]), index)
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
    /// process lifetime and reports the recovered request ids with the exact
    /// component indexes that survived. Default: no transfers survive
    /// (in-process transports).
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
    // moveItem(at:to:) is intentionally NOT redeclared here: Foundation already
    // provides it with the exact required signature, and a redeclaration would
    // shadow it (ambiguous call sites) and recurse into itself.
}
