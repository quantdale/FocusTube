import Foundation
import os
import FocusTubeCore

/// Real durable background download transport backed by a `URLSession` created
/// with `URLSessionConfiguration.background(withIdentifier:)`. The session uses
/// a stable identifier so iOS continues transfers while the app is suspended and
/// re-attaches them after the app returns to the foreground. A delegate bridge
/// forwards URLSession callbacks to per-task event handlers on the session's
/// delegate queue; all shared state is guarded by an unfair lock so both the
/// delegate queue and the calling (main) actor can mutate it safely.
public final class BackgroundDownloadTransport: NSObject, @unchecked Sendable, DownloadTransport {
    public static let sessionIdentifier = "com.quantdale.FocusTube.background"

    /// A single stable background session must exist before any view is created
    /// so the system can deliver relaunch/background completions to the delegate.
    public static let shared = BackgroundDownloadTransport()

    private struct State {
        var handlers: [Int: @Sendable (DownloadEvent) -> Void] = [:]
        var componentIndex: [Int: Int] = [:]
        var tasksByRequest: [String: [URLSessionDownloadTask]] = [:]
        var backgroundCompletionHandler: CompletionHandlerBox?
    }

    /// Sendable box so the completion handler can share the main state lock
    /// without leaking a non-Sendable closure type into `State`.
    private final class CompletionHandlerBox: @unchecked Sendable {
        let handler: () -> Void
        init(handler: @escaping () -> Void) { self.handler = handler }
    }

    private let session: URLSession
    private let bridge: Bridge
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())
    /// Filesystem seam for staging-directory setup and the synchronous
    /// delegate-queue move; injectable so move failures are deterministically
    /// testable without real I/O.
    private let files: FileManaging
    /// Durable staging area for finished component files. URLSession deletes
    /// the delegate's temp URL as soon as `didFinishDownloadingTo` returns, so
    /// the file MUST be moved here synchronously before async consumers run.
    private let stagingDirectory: URL
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "download")

    /// Background-session configuration per docs/03 defaults: background
    /// launches enabled, non-discretionary, Wi-Fi-only policy expressed by
    /// refusing cellular/constrained/expensive access, and waiting for
    /// connectivity instead of failing fast. Factored out so the flags are
    /// assertable in tests.
    public static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = false
        config.allowsConstrainedNetworkAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return config
    }

    public init(files: FileManaging = FileManager.default) {
        let config = Self.makeConfiguration()
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let staging = base.appendingPathComponent("FocusTube").appendingPathComponent("Incomplete")
        try? files.createDirectory(at: staging)
        self.files = files
        self.stagingDirectory = staging
        let bridge = Bridge()
        let session = URLSession(configuration: config, delegate: bridge, delegateQueue: nil)
        self.session = session
        self.bridge = bridge
        super.init()
        bridge.transport = self
    }

    /// Stores the completion handler handed to the app by the system for a
    /// background-URL-session wake-up. Invoked once all events for that session
    /// have been delivered.
    public func setBackgroundCompletionHandler(_ handler: (() -> Void)?) {
        let box = handler.map(CompletionHandlerBox.init)
        lock.withLock { state in
            state.backgroundCompletionHandler = box
        }
    }

    // MARK: - DownloadTransport

    public func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        for (index, component) in request.components.enumerated() {
            let task = session.downloadTask(with: component.sourceURL)
            // Durable component identity: survives relaunch so reattachment
            // restores the exact slot instead of guessing from task order.
            task.taskDescription = DownloadTransferIdentity.encode(requestID: request.id, componentIndex: index)
            lock.withLock { state in
                state.handlers[task.taskIdentifier] = onEvent
                state.componentIndex[task.taskIdentifier] = index
                state.tasksByRequest[request.id, default: []].append(task)
            }
            task.resume()
        }
    }

    public func cancel(taskID: String) async {
        let tasks = lock.withLock { state -> [URLSessionDownloadTask] in
            let tasks = state.tasksByRequest[taskID] ?? []
            for task in tasks {
                state.handlers[task.taskIdentifier] = nil
                state.componentIndex[task.taskIdentifier] = nil
            }
            state.tasksByRequest[taskID] = nil
            return tasks
        }
        for task in tasks {
            task.cancel()
        }
    }

    /// Cancels every in-flight background task and drops their handlers.
    /// Retained for explicit teardown only; relaunch reconciliation reattaches
    /// live transfers via `reattach(onEvent:)` instead of discarding them.
    public func cancelAll() {
        let captured: [URLSessionDownloadTask] = lock.withLock { state in
            let tasks = Array(state.tasksByRequest.values).flatMap { $0 }
            state.handlers.removeAll()
            state.componentIndex.removeAll()
            state.tasksByRequest.removeAll()
            return tasks
        }
        for task in captured {
            task.cancel()
        }
    }

    // MARK: - Reattachment

    /// Reattaches to download tasks that are still alive in the shared
    /// background session from a previous process lifetime. Live tasks are
    /// grouped by the request id decoded from their durable
    /// `"<requestID>#<componentIndex>"` description, per-task handlers and
    /// component indexes are re-registered under those exact indexes, and every
    /// recovered request is reported with its surviving indexes. Tasks that can
    /// no longer deliver events (already finished, cancelled, or missing a
    /// decodable identity) stay unregistered so their records reconcile as
    /// interrupted instead of hanging in `.downloading`.
    public func reattach(
        onEvent: @escaping @Sendable (_ requestID: String, _ event: DownloadEvent) -> Void
    ) async -> [ReattachedDownload] {
        let liveTasks: [URLSessionDownloadTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.compactMap { $0 as? URLSessionDownloadTask })
            }
        }

        var grouped: [String: [Int: URLSessionDownloadTask]] = [:]
        for task in liveTasks.sorted(by: { $0.taskIdentifier < $1.taskIdentifier }) {
            guard task.state == .running,
                  let (requestID, index) = DownloadTransferIdentity.decode(task.taskDescription) else { continue }
            grouped[requestID, default: [:]][index] = task
        }
        // `withLock`'s closure is `@Sendable`; capture an immutable copy.
        let groups = grouped

        lock.withLock { state in
            for (requestID, tasksByIndex) in groups {
                for (index, task) in tasksByIndex.sorted(by: { $0.key < $1.key }) {
                    guard state.handlers[task.taskIdentifier] == nil else { continue }
                    state.handlers[task.taskIdentifier] = { event in onEvent(requestID, event) }
                    state.componentIndex[task.taskIdentifier] = index
                    state.tasksByRequest[requestID, default: []].append(task)
                }
            }
        }

        return grouped.keys.sorted().map { requestID in
            ReattachedDownload(
                requestID: requestID,
                recoveredIndexes: grouped[requestID]?.keys.sorted() ?? []
            )
        }
    }

    // MARK: - Delegate bridge callbacks (called on the session delegate queue)

    fileprivate func deliverProgress(taskIdentifier: Int, bytes: Int64, total: Int64) {
        guard let (handler, index) = lock.withLock({ state -> (@Sendable (DownloadEvent) -> Void, Int)? in
            guard let handler = state.handlers[taskIdentifier],
                  let index = state.componentIndex[taskIdentifier] else { return nil }
            return (handler, index)
        }) else { return }
        handler(.progress(component: index, bytes: bytes, total: total))
    }

    fileprivate func deliverCompleted(taskIdentifier: Int, location: URL) {
        guard let (handler, index) = lock.withLock({ state -> (@Sendable (DownloadEvent) -> Void, Int)? in
            guard let handler = state.handlers[taskIdentifier],
                  let index = state.componentIndex[taskIdentifier] else { return nil }
            state.handlers[taskIdentifier] = nil
            state.componentIndex[taskIdentifier] = nil
            return (handler, index)
        }) else { return }
        handler(.completed(tempLocation: location, component: index))
    }

    fileprivate func deliverFailed(taskIdentifier: Int, error: DownloadError = .transportFailed) {
        let handler = lock.withLock { state -> (@Sendable (DownloadEvent) -> Void)? in
            guard let handler = state.handlers[taskIdentifier] else { return nil }
            state.handlers[taskIdentifier] = nil
            state.componentIndex[taskIdentifier] = nil
            return handler
        }
        handler?(.failed(error))
    }

    /// Moves a finished download out of URLSession's ephemeral temp location
    /// into durable staging, returning the staged URL — never the ephemeral
    /// input URL, which URLSession deletes the moment the delegate callback
    /// returns. A failed move is a typed storage failure, not a completion.
    fileprivate func stageComponent(_ taskIdentifier: Int, from location: URL) -> Result<URL, DownloadError> {
        let destination = stagingDirectory.appendingPathComponent("component-\(taskIdentifier)")
        try? files.removeItem(at: destination)
        do {
            try files.moveItem(at: location, to: destination)
            return .success(destination)
        } catch {
            // Launch-time directory creation may have failed silently; retry
            // creation once before giving up.
            do {
                try files.createDirectory(at: stagingDirectory)
                try files.moveItem(at: location, to: destination)
                return .success(destination)
            } catch {
                Self.logger.error("Staging move failed for component \(taskIdentifier, privacy: .public): \(String(describing: error), privacy: .private)")
                // Best effort: don't leave unreadable bytes in URLSession's
                // temporary custody past this callback.
                try? FileManager.default.removeItem(at: location)
                return .failure(.finalizationFailed)
            }
        }
    }

    fileprivate func finishEvents() {
        let boxed = lock.withLock { state -> CompletionHandlerBox? in
            let handler = state.backgroundCompletionHandler
            state.backgroundCompletionHandler = nil
            return handler
        }
        boxed?.handler()
    }

    /// Removes only the finished task from its request group so the sibling
    /// components of an adaptive download stay cancellable. The request id is
    /// decoded from the task's durable description.
    fileprivate func clearRequest(_ description: String?, taskIdentifier: Int) {
        guard let (requestID, _) = DownloadTransferIdentity.decode(description) else { return }
        lock.withLock { state in
            guard var tasks = state.tasksByRequest[requestID] else { return }
            tasks.removeAll { $0.taskIdentifier == taskIdentifier }
            if tasks.isEmpty {
                state.tasksByRequest[requestID] = nil
            } else {
                state.tasksByRequest[requestID] = tasks
            }
        }
    }

    private final class Bridge: NSObject, URLSessionDownloadDelegate {
        weak var transport: BackgroundDownloadTransport?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            transport?.deliverProgress(taskIdentifier: downloadTask.taskIdentifier, bytes: totalBytesWritten, total: totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // Non-2xx responses arrive here as a successful transfer of an
            // error body. Signed media URLs expire with 403; surface that as
            // the typed expired-URL error so callers can re-resolve and retry.
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
            if !(200..<300).contains(status) {
                try? FileManager.default.removeItem(at: location)
                transport?.deliverFailed(
                    taskIdentifier: downloadTask.taskIdentifier,
                    error: status == 403 ? .expiredMediaURL : .transportFailed
                )
                return
            }
            // URLSession deletes `location` the moment this delegate method
            // returns, while consumers process events asynchronously. Move the
            // file into durable staging synchronously, then hand off that URL.
            guard let transport else { return }
            switch transport.stageComponent(downloadTask.taskIdentifier, from: location) {
            case .success(let staged):
                transport.deliverCompleted(taskIdentifier: downloadTask.taskIdentifier, location: staged)
            case .failure(let error):
                transport.deliverFailed(taskIdentifier: downloadTask.taskIdentifier, error: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let ns = error.map { $0 as NSError }
            let cancelled = ns?.domain == NSURLErrorDomain && ns?.code == NSURLErrorCancelled
            if !cancelled, error != nil {
                transport?.deliverFailed(taskIdentifier: task.taskIdentifier)
            }
            transport?.clearRequest(task.taskDescription, taskIdentifier: task.taskIdentifier)
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            transport?.finishEvents()
        }
    }
}
