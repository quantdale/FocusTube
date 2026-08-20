import Foundation

/// Relaunch/reconciliation policy for persisted download tasks. Pure and
/// deterministic: given the persisted tasks and a filesystem check, it derives
/// the corrected post-relaunch state without touching networking or storage.
public enum DownloadReconciler {
    /// - `downloading` / `finalizing` from a previous launch cannot resume
    ///   mid-transfer and are marked interrupted (retryable).
    /// - `completed` is verified against the filesystem; a missing final file
    ///   becomes a validation failure.
    /// - `queued` / `paused` / `failed` / `idle` are left unchanged.
    public static func reconcile(
        _ tasks: [DownloadTask],
        fileExists: (URL) -> Bool
    ) -> [DownloadTask] {
        tasks.map { task in
            var updated = task
            switch task.state.status {
            case .downloading, .finalizing:
                var state = task.state
                state.status = .failed
                state.error = .interrupted
                updated.apply(state)
            case .completed:
                if !fileExists(task.destinationURL) {
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
