import Foundation

/// Planning metadata a capacity-deferred download must persist so the queue
/// survives process death. Promotion after relaunch re-resolves fresh signed
/// stream URLs through `MediaExtracting`, so this payload deliberately carries
/// NO media URLs — only what presentation and exact-quality re-planning need.
public struct QueuedDownloadMetadata: Codable, Sendable, Hashable {
    public var title: String
    public var channelTitle: String
    public var durationSeconds: TimeInterval

    public init(title: String, channelTitle: String, durationSeconds: TimeInterval) {
        self.title = title
        self.channelTitle = channelTitle
        self.durationSeconds = durationSeconds
    }
}

/// Pure admission rule for the durable download queue.
///
/// Invariants (docs/03 + DDV2-01):
/// - at most `maxConcurrent` transfers run at once;
/// - queued work is strictly FIFO — a new request may never overtake an
///   already-queued one, so any nonempty queue forces deferral regardless of
///   free slots;
/// - queued records do NOT occupy active slots. They are parked intentions,
///   not transfers, so a stranded queue can delay but never deadlock
///   admission: once actives settle below the budget, promotion proceeds.
public enum DownloadQueuePolicy {
    /// Full admission rule for NEW user requests: the concurrency budget and
    /// strict FIFO precedence both apply — nothing may overtake queued work.
    public static func shouldDefer(activeCount: Int, queuedCount: Int, maxConcurrent: Int) -> Bool {
        activeCount >= maxConcurrent || queuedCount > 0
    }

    /// Budget-only rule for PROMOTED queue heads: they have already earned
    /// their FIFO position (their sibling `.queued` records sit behind them in
    /// the session queue), so only the concurrency bound applies.
    public static func exceedsBudget(activeCount: Int, maxConcurrent: Int) -> Bool {
        activeCount >= maxConcurrent
    }
}
