import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// H3-02 regression pins:
/// - HB-022: download failures present where they originate. Queue-promotion
///   settlements never write the shared `lastFailure` alert (which only the
///   video page presents); they surface as failed rows in the Downloads
///   projection instead.
/// - HB-023: planned duration persists additively at enqueue and re-runs
///   truthful storage admission on failed-row retries; unknown durations keep
///   the historical skip-pre-check behavior.
@MainActor
final class DownloadFailureOwnershipTests: XCTestCase {
    private func combinedMedia(videoID: String, resolution: Int) -> ResolvedMedia {
        let stream = MediaStream(
            id: "https://example.com/\(videoID)-\(resolution)",
            videoID: videoID,
            resolution: resolution,
            kind: .combined,
            nativePlayable: true,
            container: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a",
            sourceURL: URL(string: "https://example.com/\(videoID)-\(resolution)")!,
            expiresAt: nil
        )
        return ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: [stream],
            videoOnly: [],
            audioOnly: []
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private struct NoopTransportForHB23: DownloadTransport {
        func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
        func cancel(taskID: String) async {}
    }

    /// Routes each task id to its own transport behavior so one manager can
    /// gate slot-holders while failing a promoted job deterministically.
    private final class RoutedTransport: DownloadTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var gated: Set<String> = []
        private var failing: Set<String> = []
        private var beginsByTask: [String: Int] = [:]
        let tempLocation = URL(fileURLWithPath: "/tmp/h3-ownership-temp.mp4")

        func gate(_ taskID: String) { lock.withLock { gated.insert(taskID) } }
        func fail(_ taskID: String) { lock.withLock { failing.insert(taskID) } }
        func releaseAll() { lock.withLock { gated.removeAll() } }
        func beginCount(for taskID: String) -> Int { lock.withLock { beginsByTask[taskID, default: 0] } }

        func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
            lock.withLock { beginsByTask[request.id, default: 0] += 1 }
            let (isGated, isFailing) = lock.withLock {
                (gated.contains(request.id), failing.contains(request.id))
            }
            if isFailing {
                onEvent(.failed(.transportFailed))
                return
            }
            onEvent(.progress(component: 0, bytes: 0, total: 100))
            while lock.withLock({ gated.contains(request.id) }) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            onEvent(.completed(tempLocation: tempLocation, component: 0))
        }

        func cancel(taskID: String) async {
            releaseAll()
        }
    }

    private struct TinyStorage: StorageProviding {
        func availableCapacity(for url: URL) -> Int64 { 0 }
    }

    private struct FixedResolver: MediaExtracting, @unchecked Sendable {
        let mediaByID: [String: ResolvedMedia]
        func resolve(videoID: String) async throws -> ResolvedMedia {
            guard let media = mediaByID[videoID] else { throw ExtractionError.unavailable }
            return media
        }
    }

    private func makeService(
        transport: DownloadTransport,
        storage: StorageProviding = VolumeStorage(),
        mediaByID: [String: ResolvedMedia] = [:]
    ) throws -> (DownloadService, DownloadManager) {
        let manager = DownloadManager(
            transport: transport,
            context: ModelContext(try makeContainer()),
            storage: storage,
            validate: nil
        )
        let librarySchema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let library = LibraryStore(context: ModelContext(try ModelContainer(for: librarySchema, configurations: [
            ModelConfiguration(schema: librarySchema, isStoredInMemoryOnly: true)
        ])))
        let service = DownloadService(
            extractor: FixedResolver(mediaByID: mediaByID),
            downloadManager: manager,
            library: library,
            mediaDirectory: URL(fileURLWithPath: "/tmp/h3-ownership-media")
        )
        return (service, manager)
    }

    private func waitUntil(
        _ condition: () -> Bool,
        timeout: TimeInterval = 5,
        _ message: String
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message)
    }

    // MARK: - HB-022

    func testPromotedJobFailureNeverWritesSharedLastFailure() async throws {
        let transport = RoutedTransport()
        transport.gate("v1-720")
        transport.gate("v2-720")
        let resolver = FixedResolver(mediaByID: [
            "v1": combinedMedia(videoID: "v1", resolution: 720),
            "v2": combinedMedia(videoID: "v2", resolution: 720),
            "v3": combinedMedia(videoID: "v3", resolution: 720),
            "v4": combinedMedia(videoID: "v4", resolution: 360)
        ])
        let manager = DownloadManager(
            transport: transport,
            context: ModelContext(try makeContainer()),
            validate: nil
        )
        let librarySchema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let library = LibraryStore(context: ModelContext(try ModelContainer(for: librarySchema, configurations: [
            ModelConfiguration(schema: librarySchema, isStoredInMemoryOnly: true)
        ])))
        let service = DownloadService(
            extractor: resolver,
            downloadManager: manager,
            library: library,
            mediaDirectory: URL(fileURLWithPath: "/tmp/h3-ownership-media")
        )

        // v1/v2 fill both logical slots mid-flight; v3 defers into the durable
        // queue and v4 parks behind it FIFO.
        await service.download(videoID: "v1", title: "V1", channelTitle: "C", quality: .p720)
        await service.download(videoID: "v2", title: "V2", channelTitle: "C", quality: .p720)
        await service.download(videoID: "v3", title: "V3", channelTitle: "C", quality: .p720)
        await service.download(videoID: "v4", title: "V4", channelTitle: "C", quality: .p360)

        // The promoted head (v3) fails its transfer; releasing the gates lets
        // both held slots settle so promotion runs.
        transport.fail("v3-720")
        transport.releaseAll()

        try await waitUntilThrowing({ transport.beginCount(for: "v3-720") == 1 },
                                    "promoted job was never started")
        try await waitUntilThrowing({
            manager.failedTasks.contains { $0.id == "v3-720" }
        }, "failed promotion must surface as a failed row in the Downloads projection")

        // HB-022 core assertion: the shared alert surface stays untouched by
        // settlement-owned failures.
        let failure = await service.lastFailure
        XCTAssertNil(failure, "promotion failures must not poison the shared alert surface")
    }

    func testUserRequestedFailureStillWritesLastFailure() async throws {
        let transport = RoutedTransport()
        transport.fail("u1-720")
        let (service, _) = try makeService(
            transport: transport,
            mediaByID: ["u1": combinedMedia(videoID: "u1", resolution: 720)]
        )

        await service.download(videoID: "u1", title: "U1", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure?.videoID, "u1")
        XCTAssertEqual(failure?.error, .transportFailed)
    }

    // MARK: - HB-023

    func testEnqueuePersistsPlannedDurationReadableForRetry() async throws {
        let manager = DownloadManager(
            transport: NoopTransportForHB23(),
            context: ModelContext(try makeContainer()),
            validate: nil
        )
        let request = DownloadRequest(
            id: "hb23-a-720",
            videoID: "hb23a",
            streamID: "s",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/a")!,
            destinationURL: URL(fileURLWithPath: "/tmp/hb23/a/720/media.mp4")
        )
        _ = await manager.enqueue(request, bypassQueuePrecedence: true, plannedDurationSeconds: 631)

        XCTAssertEqual(manager.plannedDurationSeconds(taskID: "hb23-a-720"), 631)
    }

    func testLegacyRowWithoutPlannedDurationReadsNil() async throws {
        let manager = DownloadManager(
            transport: NoopTransportForHB23(),
            context: ModelContext(try makeContainer()),
            validate: nil
        )
        let request = DownloadRequest(
            id: "legacy-row-720",
            videoID: "legacyrow",
            streamID: "s",
            resolution: 720,
            sourceURL: URL(string: "https://example.com/l")!,
            destinationURL: URL(fileURLWithPath: "/tmp/hb23/l/720/media.mp4")
        )
        _ = await manager.enqueue(request, bypassQueuePrecedence: true)
        XCTAssertNil(manager.plannedDurationSeconds(taskID: "legacy-row-720"),
                     "rows created before HB-023 keep the unknown-duration retry behavior")
    }

    func testKnownDurationOnRetryRunsTruthfulStorageAdmissionUpFront() async throws {
        // A duration-carrying attempt against an always-full volume must
        // refuse BEFORE any transfer begins (typed storageRefused), proving
        // the duration reaches the admission pre-check that a zero-duration
        // retry would skip.
        let transport = RoutedTransport()
        let (service, manager) = try makeService(
            transport: transport,
            storage: TinyStorage(),
            mediaByID: ["big": combinedMedia(videoID: "big", resolution: 720)]
        )

        await service.download(videoID: "big", title: "B", channelTitle: "C", quality: .p720, durationSeconds: 7_200)

        XCTAssertEqual(manager.liveTasks.count, 0, "storage refusal must precede any live transfer")
        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .storageRefused)
    }

    private func waitUntilThrowing(
        _ condition: () -> Bool,
        _ message: String,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message)
    }
}
