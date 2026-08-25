import XCTest
@testable import FocusTubeCore

private struct OrderingNoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

/// Finalization-friendly fake: files exist with nonzero size and replacement
/// succeeds, so single-component completion parks exactly in the injected
/// validator without touching the real filesystem.
private struct OrderingFakeFileManager: FileManaging {
    func fileExists(at url: URL) -> Bool { true }
    func size(of url: URL) -> Int64 { 1024 }
    func createDirectory(at url: URL) throws {}
    func replaceItem(at destination: URL, withItemAt item: URL) throws {}
    func moveItem(at item: URL, to destination: URL) throws {}
    func removeItem(at url: URL) throws {}
}

/// Records the post-event status of every applied event, in apply order.
private final class StatusJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [DownloadStatus] = []

    func record(_ status: DownloadStatus) {
        lock.lock()
        statuses.append(status)
        lock.unlock()
    }

    var recorded: [DownloadStatus] {
        lock.lock()
        defer { lock.unlock() }
        return statuses
    }
}

/// One-shot gate used to park the validate seam mid-finalization until the
/// test releases it, so a second event can be staged while the first is still
/// in flight.
private final class ValidationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let waiters = self.waiters
        self.waiters = []
        lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

/// Coverage for HB-012: per-task events must keep applying strictly in arrival
/// order (and `handle` must not return before its event is applied) now that
/// event application no longer allocates an unstructured Task per delivery.
final class DownloadCoordinatorEventOrderingTests: XCTestCase {
    private func makeRequest(id: String, components: [DownloadComponent]) -> DownloadRequest {
        DownloadRequest(
            id: id,
            videoID: "vid",
            resolution: 720,
            destinationURL: URL(fileURLWithPath: "/tmp/\(id).mp4"),
            components: components
        )
    }

    // MARK: - rapid concurrent progress

    func testConcurrentProgressAcrossComponentsAggregatesExactly() async {
        let coordinator = DownloadCoordinator(
            transport: OrderingNoopTransport(),
            fileManager: OrderingFakeFileManager()
        )
        let componentCount = 20
        let components = (0..<componentCount).map {
            DownloadComponent(streamID: "s\($0)", sourceURL: URL(string: "https://example.com/s\($0)")!)
        }
        _ = await coordinator.enqueue(makeRequest(id: "storm", components: components))

        // Every component reports concurrently; slots commute, so any valid
        // serialization must produce the exact same aggregate — a lost or
        // duplicated update cannot.
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<componentCount {
                group.addTask {
                    await coordinator.handle(
                        .progress(component: index, bytes: Int64(index + 1), total: 1_000),
                        taskID: "storm"
                    )
                }
            }
        }

        let task = await coordinator.task("storm")
        XCTAssertEqual(task?.state.bytesDownloaded, Int64((1...componentCount).reduce(0, +)))
        XCTAssertEqual(task?.state.totalBytes, Int64(componentCount * 1_000))
    }

    // MARK: - completed/failed ordering across in-flight finalization

    /// HB-017 semantics: a failure delivered BEHIND an in-flight finalization
    /// still serializes through the event chain (it can never interleave with
    /// or preempt the parked finalization), but once completion has settled,
    /// the completion is FINAL — validated, published media is never regressed
    /// to a failed row by a late/duplicate transport failure.
    func testLateFailureBehindInFlightFinalizationSerializesButCannotRegressCompletion() async {
        let gate = ValidationGate()
        let journal = StatusJournal()
        let coordinator = DownloadCoordinator(
            transport: OrderingNoopTransport(),
            fileManager: OrderingFakeFileManager(),
            validate: { _ in await gate.wait() }
        )
        _ = await coordinator.enqueue(makeRequest(id: "ordered", components: [
            DownloadComponent(streamID: "s0", sourceURL: URL(string: "https://example.com/s0")!)
        ]))
        await coordinator.begin("ordered")

        // First arrival: completes the only component. Its finalization parks
        // in the gated validator before it can settle.
        let completing = Task {
            await coordinator.handle(
                .completed(tempLocation: URL(fileURLWithPath: "/tmp/tmp-ordered.mp4"), component: 0),
                taskID: "ordered",
                onUpdate: { journal.record($0.state.status) }
            )
        }
        await waitFor(coordinator, taskID: "ordered", toReach: .finalizing)

        // Second arrival while the first is mid-finalization: it must queue
        // behind the in-flight event instead of interleaving with it.
        let failing = Task {
            await coordinator.handle(
                .failed(.transportFailed),
                taskID: "ordered",
                onUpdate: { journal.record($0.state.status) }
            )
        }
        await gate.open()

        await completing.value
        await failing.value

        // Applied strictly in arrival order: completion settled first; the
        // late failure was serialized behind it and then correctly ignored —
        // a validated, published download cannot regress to failed (HB-017).
        let task = await coordinator.task("ordered")
        XCTAssertEqual(task?.state.status, .completed)
        XCTAssertNil(task?.state.error)
        XCTAssertEqual(journal.recorded, [.completed])
    }

    private func waitFor(
        _ coordinator: DownloadCoordinator,
        taskID: String,
        toReach status: DownloadStatus,
        timeoutSeconds: Double = 5
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let task = await coordinator.task(taskID), task.state.status == status {
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("task \(taskID) never reached \(status)")
    }
}
