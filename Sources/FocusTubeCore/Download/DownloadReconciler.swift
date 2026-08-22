import Foundation

/// Relaunch/reconciliation policy for persisted download tasks. Pure and
/// deterministic: given the persisted tasks and a filesystem check, it derives
/// the corrected post-relaunch state without touching networking or storage.
public enum DownloadReconciler {
    /// - `downloading` / `finalizing` / `resolving` / `validating` / `muxing` /
    ///   `waitingForRetry` / `reResolving` from a previous launch cannot resume
    ///   mid-transfer and are marked interrupted (retryable).
    /// - `completed` is verified against the filesystem; a missing or
    ///   zero-byte final file becomes a validation failure (finalization
    ///    itself requires existence AND size > 0, so reconciliation must not
    ///    settle a truncated file as playable).
    /// - `queued` / `paused` / `failed` / `idle` are left unchanged.
    public static func reconcile(
        _ tasks: [DownloadTask],
        fileExists: (URL) -> Bool,
        sizeOf: (URL) -> Int64
    ) -> [DownloadTask] {
        tasks.map { task in
            var updated = task
            switch task.state.status {
            case .downloading, .finalizing, .resolving, .validating,
                 .muxing, .waitingForRetry, .reResolving:
                var state = task.state
                state.status = .failed
                state.error = .interrupted
                updated.apply(state)
            case .completed:
                if !fileExists(task.destinationURL) || sizeOf(task.destinationURL) <= 0 {
                    var state = task.state
                    state.status = .failed
                    state.error = .validationFailed
                    updated.apply(state)
                }
            default:
                break
            }
            return updated
        }
    }
}
