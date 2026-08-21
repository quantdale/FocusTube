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

    public override init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = 4
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
        lock.withLock { state in
            state.backgroundCompletionHandler = handler.map(CompletionHandlerBox.init)
        }
    }

    // MARK: - DownloadTransport

    public func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        for (index, component) in request.components.enumerated() {
            let task = session.downloadTask(with: component.sourceURL)
            task.taskDescription = request.id
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
        var captured: [URLSessionDownloadTask] = []
        lock.withLock { state in
            captured = Array(state.tasksByRequest.values).flatMap { $0 }
            state.handlers.removeAll()
            state.componentIndex.removeAll()
            state.tasksByRequest.removeAll()
        }
        for task in captured {
            task.cancel()
        }
    }

    // MARK: - Reattachment

    /// Reattaches to download tasks that are still alive in the shared
    /// background session from a previous process lifetime. Live tasks are
    /// grouped by their `taskDescription` (the request id), per-task handlers
    /// and component indexes are re-registered so delegate callbacks flow to
    /// `onEvent`, and every recovered request is reported with its live
    /// component count. Tasks that can no longer deliver events (already
    /// finished, cancelled, or missing their request id) stay unregistered so
    /// their records reconcile as interrupted instead of hanging in
    /// `.downloading`.
    public func reattach(
        onEvent: @escaping @Sendable (_ requestID: String, _ event: DownloadEvent) -> Void
    ) async -> [ReattachedDownload] {
        let liveTasks: [URLSessionDownloadTask] = await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.compactMap { $0 as? URLSessionDownloadTask })
            }
        }

        var grouped: [String: [URLSessionDownloadTask]] = [:]
        for task in liveTasks.sorted(by: { $0.taskIdentifier < $1.taskIdentifier }) {
            guard task.state == .running,
                  let requestID = task.taskDescription, !requestID.isEmpty else { continue }
            grouped[requestID, default: []].append(task)
        }

        lock.withLock { state in
            for (requestID, tasks) in grouped {
                for (index, task) in tasks.enumerated() {
                    guard state.handlers[task.taskIdentifier] == nil else { continue }
                    state.handlers[task.taskIdentifier] = { event in onEvent(requestID, event) }
                    state.componentIndex[task.taskIdentifier] = index
                    state.tasksByRequest[requestID, default: []].append(task)
                }
            }
        }

        return grouped.keys.sorted().map { requestID in
            ReattachedDownload(requestID: requestID, componentCount: grouped[requestID]?.count ?? 0)
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

    fileprivate func deliverFailed(taskIdentifier: Int) {
        let handler = lock.withLock { state -> (@Sendable (DownloadEvent) -> Void)? in
            guard let handler = state.handlers[taskIdentifier] else { return nil }
            state.handlers[taskIdentifier] = nil
            state.componentIndex[taskIdentifier] = nil
            return handler
        }
        handler?(.failed(.transportFailed))
    }

    fileprivate func finishEvents() {
        let boxed = lock.withLock { state -> CompletionHandlerBox? in
            let handler = state.backgroundCompletionHandler
            state.backgroundCompletionHandler = nil
            return handler
        }
        boxed?.handler()
    }

    fileprivate func clearRequest(_ requestID: String) {
        lock.withLock { state in
            state.tasksByRequest.removeValue(forKey: requestID)
        }
    }

    private class Bridge: NSObject, URLSessionDownloadDelegate {
        weak var transport: BackgroundDownloadTransport?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            transport?.deliverProgress(taskIdentifier: downloadTask.taskIdentifier, bytes: totalBytesWritten, total: totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            transport?.deliverCompleted(taskIdentifier: downloadTask.taskIdentifier, location: location)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let ns = error.map { $0 as NSError }
            let cancelled = ns?.domain == NSURLErrorDomain && ns?.code == NSURLErrorCancelled
            if !cancelled, error != nil {
                transport?.deliverFailed(taskIdentifier: task.taskIdentifier)
            }
            transport?.clearRequest(task.taskDescription ?? "")
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            transport?.finishEvents()
        }
    }
}
