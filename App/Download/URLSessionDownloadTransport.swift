import Foundation
import FocusTubeCore

/// Concrete `DownloadTransport` backed by `URLSession`. This foreground
/// `downloadTask` path proves the allowed combined stream can be fetched through
/// the URLSession transport; durable background transfer is added in WP-005.
public struct URLSessionDownloadTransport: DownloadTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        let task = session.downloadTask(with: request.sourceURL) { location, _, error in
            if let _ = error {
                onEvent(.failed(.transportFailed))
                return
            }
            guard let location else {
                onEvent(.failed(.transportFailed))
                return
            }
            onEvent(.completed(tempLocation: location))
        }
        task.resume()
    }

    public func cancel(taskID: String) async {
        // Foreground shared-session transport has no task registry to cancel by
        // ID; durable cancellation arrives with the background transport in WP-005.
    }
}
