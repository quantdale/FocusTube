import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

private struct FakeExtractor: MediaExtracting {
    let result: Result<ResolvedMedia, ExtractionError>

    func resolve(videoID: String) async throws -> ResolvedMedia {
        try result.get()
    }
}

private struct NoopTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {}
    func cancel(taskID: String) async {}
}

private final class FailingTransport: DownloadTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var beginCount = 0

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        lock.withLock { beginCount += 1 }
        onEvent(.failed(.transportFailed))
    }

    func cancel(taskID: String) async {}
}

/// Emits one completed component event pointing at a pre-written temp file so
/// the coordinator's validation/finalization runs over the real filesystem.
private struct CompletingTransport: DownloadTransport {
    let tempLocation: URL

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        onEvent(.completed(tempLocation: tempLocation, component: 0))
    }

    func cancel(taskID: String) async {}
}

/// First begin reports an expired signed URL; the retry (after re-resolution)
/// completes so the service's bounded automatic-retry path can be tested.
private final class ExpiredThenCompletingTransport: DownloadTransport, @unchecked Sendable {
    let tempLocation: URL
    private var hasFailedOnce = false

    init(tempLocation: URL) {
        self.tempLocation = tempLocation
    }

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        if !hasFailedOnce {
            hasFailedOnce = true
            onEvent(.failed(.expiredMediaURL))
            return
        }
        onEvent(.completed(tempLocation: tempLocation, component: 0))
    }

    func cancel(taskID: String) async {}
}

/// Holds each transfer's completion behind a released gate so a download can be
/// observed mid-flight; emits one progress event on begin so the manager's live
/// projection (and the service's in-flight check) populates immediately.
private final class GatedTransport: DownloadTransport, @unchecked Sendable {
    let tempLocation: URL
    private let lock = NSLock()
    private var released = false
    private(set) var beginCount = 0

    init(tempLocation: URL) {
        self.tempLocation = tempLocation
    }

    func release() {
        lock.withLock { released = true }
    }

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        lock.withLock { beginCount += 1 }
        onEvent(.progress(component: 0, bytes: 0, total: 100))
        while true {
            let done = lock.withLock { released }
            if done { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        onEvent(.completed(tempLocation: tempLocation, component: 0))
    }

    /// Cancelling a gated transfer must end its begin loop promptly instead of
    /// leaving an eternal poll task behind in the test process.
    func cancel(taskID: String) async {
        release()
    }
}

/// Fails every transfer until switched to completing; counts begins so tests can
/// assert exactly how many transfer attempts the service made.
private final class SwitchableTransport: DownloadTransport, @unchecked Sendable {
    let tempLocation: URL
    private let lock = NSLock()
    private var failing = true
    private(set) var beginCount = 0

    init(tempLocation: URL) {
        self.tempLocation = tempLocation
    }

    func completeSubsequentTransfers() {
        lock.withLock { failing = false }
    }

    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
        let (beginCountNow, failingNow) = lock.withLock { (beginCount + 1, failing) }
        beginCount = beginCountNow
        if failingNow {
            onEvent(.failed(.transportFailed))
        } else {
            onEvent(.completed(tempLocation: tempLocation, component: 0))
        }
    }

    func cancel(taskID: String) async {}
}

/// Per-video resolver so concurrent downloads exercise independent media;
/// counts resolutions to prove retries re-resolve instead of replaying URLs.
private final class PerVideoExtractor: MediaExtracting, @unchecked Sendable {
    let mediaByID: [String: ResolvedMedia]
    private let lock = NSLock()
    private var resolves: [String: Int] = [:]

    init(mediaByID: [String: ResolvedMedia]) {
        self.mediaByID = mediaByID
    }

    func resolveCount(for videoID: String) -> Int {
        lock.withLock { resolves[videoID, default: 0] }
    }

    func resolve(videoID: String) async throws -> ResolvedMedia {
        lock.withLock { resolves[videoID, default: 0] += 1 }
        guard let media = mediaByID[videoID] else { throw ExtractionError.unavailable }
        return media
    }
}

@MainActor
final class DownloadServiceTests: XCTestCase {
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

    @MainActor
    private func makeManager() throws -> DownloadManager {
        let schema = Schema([DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return DownloadManager(
            transport: NoopTransport(),
            context: ModelContext(container),
            validate: nil
        )
    }

    @MainActor
    private func makeLibrary() throws -> LibraryStore {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return LibraryStore(context: ModelContext(container))
    }

    /// Polls until the condition holds or the timeout elapses, failing the test
    /// with `message`; used to observe gated mid-flight state deterministically.
    @MainActor
    private func waitUntil(
        _ condition: () async -> Bool,
        timeout: TimeInterval = 5,
        _ message: String
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message)
    }

    func testExtractionFailureSurfacesTypedError() async throws {
        let service = await DownloadService(
            extractor: FakeExtractor(result: .failure(.unavailable)),
            downloadManager: try await makeManager(),
            library: try await makeLibrary()
        )
        await service.download(videoID: "v1", title: "T", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .extractionFailed)
        XCTAssertEqual(failure?.videoID, "v1")
        XCTAssertEqual(failure?.title, "T")
        XCTAssertEqual(failure?.quality, .p720)
        XCTAssertFalse(failure?.userMessage.isEmpty ?? true)
    }

    func testRequestedQualityUnavailableSurfacesTypedError() async throws {
        // Only 360p exists; requesting 720p must fail without downgrading.
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v2", resolution: 360))),
            downloadManager: try await makeManager(),
            library: try await makeLibrary()
        )
        await service.download(videoID: "v2", title: "T", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .requestedQualityUnavailable)
    }

    func testNoAllowedStreamSurfacesTypedError() async throws {
        let empty = ResolvedMedia(videoID: "v3", extractedAt: Date(), combined: [], videoOnly: [], audioOnly: [])
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(empty)),
            downloadManager: try await makeManager(),
            library: try await makeLibrary()
        )
        await service.download(videoID: "v3", title: "T", channelTitle: "C", quality: .p480)

        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .noAllowedStream)
    }

    func testTransportFailureSurfacesTypedError() async throws {
        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v4", resolution: 720))),
            downloadManager: DownloadManager(
                transport: FailingTransport(),
                context: ModelContext(try makeContainer()),
                validate: nil
            ),
            library: library
        )
        await service.download(videoID: "v4", title: "T", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .transportFailed)
        let downloaded = await library.downloaded
        XCTAssertTrue(downloaded.isEmpty)
    }

    func testSuccessRegistersFinalizedMediaWithoutFailure() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let destination = mediaDirectory
            .appendingPathComponent("v5")
            .appendingPathComponent("720")
            .appendingPathComponent("media.mp4")

        let temp = root.appendingPathComponent("component-\(UUID().uuidString).mp4")
        // Pre-create the destination so finalization exercises replaceItemAt's
        // documented existing-destination path (first-download creation is a
        // coordinator/filesystem concern covered elsewhere). The directory
        // chain (including root) must exist before any file writes.
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02]).write(to: temp)
        try Data([0x00]).write(to: destination)

        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v5", resolution: 720))),
            downloadManager: DownloadManager(
                transport: CompletingTransport(tempLocation: temp),
                context: ModelContext(try makeContainer()),
                validate: nil
            ),
            library: library,
            mediaDirectory: mediaDirectory
        )
        await service.download(videoID: "v5", title: "T", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertNil(failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let downloaded = await library.downloaded
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.videoID, "v5")
        XCTAssertEqual(downloaded.first?.sizeBytes, 2)
    }

    func testExpiredURLRetriesOnceWithFreshResolutionAndSucceeds() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let destination = mediaDirectory
            .appendingPathComponent("v6")
            .appendingPathComponent("720")
            .appendingPathComponent("media.mp4")
        let temp = root.appendingPathComponent("component-\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02]).write(to: temp)
        try Data([0x00]).write(to: destination)

        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v6", resolution: 720))),
            downloadManager: DownloadManager(
                transport: ExpiredThenCompletingTransport(tempLocation: temp),
                context: ModelContext(try makeContainer()),
                validate: nil
            ),
            library: library,
            mediaDirectory: mediaDirectory
        )
        await service.download(videoID: "v6", title: "T", channelTitle: "C", quality: .p720)

        let failure = await service.lastFailure
        XCTAssertNil(failure)
        let downloaded = await library.downloaded
        XCTAssertEqual(downloaded.count, 1)
    }

    func testConcurrentDuplicateDownloadDoesNotResetInFlightTask() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let destination = mediaDirectory
            .appendingPathComponent("v7")
            .appendingPathComponent("720")
            .appendingPathComponent("media.mp4")
        let temp = root.appendingPathComponent("component-\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02]).write(to: temp)
        try Data([0x00]).write(to: destination)

        let gated = GatedTransport(tempLocation: temp)
        let manager = DownloadManager(transport: gated, context: ModelContext(try makeContainer()), validate: nil)
        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v7", resolution: 720))),
            downloadManager: manager,
            library: library,
            mediaDirectory: mediaDirectory
        )

        let first = Task {
            await service.download(videoID: "v7", title: "T", channelTitle: "C", quality: .p720)
        }
        await waitUntil({ service.isInFlight(videoID: "v7", quality: .p720) },
                        "first download never appeared in flight")

        // A concurrent duplicate start must be refused without re-enqueueing:
        // a second enqueue would reset the coordinator task to .queued while
        // the first transfer's events are still arriving.
        await service.download(videoID: "v7", title: "T", channelTitle: "C", quality: .p720)
        XCTAssertEqual(gated.beginCount, 1)
        let inFlight = await manager.coordinatorTask("v7-720")
        XCTAssertEqual(inFlight?.state.status, .downloading)

        gated.release()
        await first.value

        let failure = await service.lastFailure
        XCTAssertNil(failure)
        let downloaded = await library.downloaded
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.videoID, "v7")
    }

    func testCancelMarksRecordCancelledAndSurfacesTypedFailure() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let gated = GatedTransport(tempLocation: root.appendingPathComponent("component.mp4"))
        let manager = DownloadManager(transport: gated, context: ModelContext(try makeContainer()), validate: nil)
        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v8", resolution: 720))),
            downloadManager: manager,
            library: library,
            mediaDirectory: root.appendingPathComponent("Media")
        )

        let running = Task {
            await service.download(videoID: "v8", title: "T", channelTitle: "C", quality: .p720)
        }
        await waitUntil({ service.isInFlight(videoID: "v8", quality: .p720) },
                        "download never appeared in flight")

        await service.cancel(videoID: "v8", quality: .p720)
        await running.value

        let failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .cancelled)
        XCTAssertEqual(failure?.quality, .p720)
        let records = await manager.records
        let record = records.first { $0.id == "v8-720" }
        XCTAssertEqual(record?.state.status, .failed)
        XCTAssertEqual(record?.state.error, .cancelled)
    }

    func testAutoRetryIgnoresFailureFromOtherQuality() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let destination = mediaDirectory
            .appendingPathComponent("v9")
            .appendingPathComponent("720")
            .appendingPathComponent("media.mp4")
        let temp = root.appendingPathComponent("component-\(UUID().uuidString).mp4")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02]).write(to: temp)
        try Data([0x00]).write(to: destination)

        func stream(_ videoID: String, resolution: Int) -> MediaStream {
            MediaStream(
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
        }
        let bothQualities = ResolvedMedia(
            videoID: "v9",
            extractedAt: Date(),
            combined: [stream("v9", resolution: 360), stream("v9", resolution: 720)],
            videoOnly: [],
            audioOnly: []
        )

        let switchable = SwitchableTransport(tempLocation: temp)
        let manager = DownloadManager(transport: switchable, context: ModelContext(try makeContainer()), validate: nil)
        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(bothQualities)),
            downloadManager: manager,
            library: library,
            mediaDirectory: mediaDirectory
        )

        // Seed a same-video failure at 360p: it fails, legitimately auto-retries
        // (same video+quality), and fails again, leaving its failure on record.
        await service.download(videoID: "v9", title: "T", channelTitle: "C", quality: .p360)
        XCTAssertEqual(switchable.beginCount, 2)
        var failure = await service.lastFailure
        XCTAssertEqual(failure?.quality, .p360)
        XCTAssertEqual(failure?.error, .transportFailed)

        // The 720p transfer succeeds on its first attempt; the stale 360p
        // failure must not cross-trigger another attempt for this quality.
        switchable.completeSubsequentTransfers()
        await service.download(videoID: "v9", title: "T", channelTitle: "C", quality: .p720)
        XCTAssertEqual(switchable.beginCount, 3)

        failure = await service.lastFailure
        XCTAssertEqual(failure?.quality, .p360)
        let downloaded = await library.downloaded
        XCTAssertEqual(downloaded.count, 1)
        XCTAssertEqual(downloaded.first?.resolution, 720)
    }

    func testConcurrentFailuresDoNotCrossContaminateRetries() async throws {
        // Two downloads fail at once. Each retry decision must consume its own
        // local outcome: exactly one automatic retry per download (2 begins
        // each), and neither failure suppresses nor duplicates the other's.
        let failing = FailingTransport()
        let extractor = PerVideoExtractor(mediaByID: [
            "va": combinedMedia(videoID: "va", resolution: 720),
            "vb": combinedMedia(videoID: "vb", resolution: 480)
        ])
        let service = await DownloadService(
            extractor: extractor,
            downloadManager: DownloadManager(
                transport: failing,
                context: ModelContext(try makeContainer()),
                validate: nil
            ),
            library: try await makeLibrary()
        )

        async let a: Void = service.download(videoID: "va", title: "A", channelTitle: "C", quality: .p720)
        async let b: Void = service.download(videoID: "vb", title: "B", channelTitle: "C", quality: .p480)
        _ = await (a, b)

        XCTAssertEqual(failing.beginCount, 4)
        XCTAssertEqual(extractor.resolveCount(for: "va"), 2)
        XCTAssertEqual(extractor.resolveCount(for: "vb"), 2)
    }

    func testRapidDuplicateDownloadStartsExactlyOneTransfer() async throws {
        // Two back-to-back starts without waiting for progress: admission is
        // reserved synchronously, so exactly one transfer may begin. The first
        // start runs in its own task; wait until it has actually reached the
        // transport so the second call below is guaranteed to be the refused
        // duplicate rather than racing it for the reservation.
        let gated = GatedTransport(tempLocation: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("unused-\(UUID().uuidString).mp4"))
        let manager = DownloadManager(transport: gated, context: ModelContext(try makeContainer()), validate: nil)
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "vd", resolution: 720))),
            downloadManager: manager,
            library: try await makeLibrary()
        )

        let a = Task {
            await service.download(videoID: "vd", title: "T", channelTitle: "C", quality: .p720)
        }
        await waitUntil({ gated.beginCount == 1 }, "first transfer never began")

        // Second rapid start while the first is mid-flight: must be refused
        // synchronously by admission, never re-enqueueing or re-beginning.
        await service.download(videoID: "vd", title: "T", channelTitle: "C", quality: .p720)
        XCTAssertEqual(gated.beginCount, 1)

        gated.release()
        await a.value
    }

    func testThirdConcurrentDownloadStaysQueuedUntilSlotFrees() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let temp = root.appendingPathComponent("component.mp4")
        try Data([0x01]).write(to: temp)
        let gated = GatedTransport(tempLocation: temp)
        let manager = DownloadManager(transport: gated, context: ModelContext(try makeContainer()), validate: nil)
        let service = await DownloadService(
            extractor: PerVideoExtractor(mediaByID: [
                "v20": combinedMedia(videoID: "v20", resolution: 720),
                "v21": combinedMedia(videoID: "v21", resolution: 720),
                "v22": combinedMedia(videoID: "v22", resolution: 720)
            ]),
            downloadManager: manager,
            library: try await makeLibrary(),
            mediaDirectory: root.appendingPathComponent("Media")
        )

        let first = Task { await service.download(videoID: "v20", title: "1", channelTitle: "C", quality: .p720) }
        let second = Task { await service.download(videoID: "v21", title: "2", channelTitle: "C", quality: .p720) }
        await waitUntil({ [manager] in
            let firstStarted = await manager.coordinatorTask("v20-720")
            let secondStarted = await manager.coordinatorTask("v21-720")
            return firstStarted != nil && secondStarted != nil
        }, "first two transfers never started")
        XCTAssertEqual(gated.beginCount, 2)

        // docs/03: at most two concurrent logical downloads — the third
        // persists as .queued without starting a transfer.
        let third = Task { await service.download(videoID: "v22", title: "3", channelTitle: "C", quality: .p720) }
        await waitUntil({ [service, manager] in
            // `await` cannot sit on the right of a comparison operator; hoist
            // each async read into a local before combining.
            let stillInFlight = await service.isInFlight(videoID: "v22", quality: .p720)
            let parked = await manager.records.contains { $0.id == "v22-720" && $0.state.status == .queued }
            return !stillInFlight && parked
        }, "third download never parked as queued")
        let thirdTask = await manager.coordinatorTask("v22-720")
        XCTAssertNil(thirdTask)
        XCTAssertEqual(gated.beginCount, 2)

        // Settling a job frees its slot; the oldest queued request promotes FIFO.
        gated.release()
        await first.value
        await second.value
        await waitUntil({ [manager] in
            let promoted = await manager.coordinatorTask("v22-720")
            return promoted != nil
        }, "queued download was never promoted after a slot freed")
        XCTAssertEqual(gated.beginCount, 3)

        gated.release()
        await third.value
    }

    func testCancelFreesSlotAndPromotesQueuedDownload() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let temp = root.appendingPathComponent("component.mp4")
        try Data([0x01]).write(to: temp)
        let gated = GatedTransport(tempLocation: temp)
        let manager = DownloadManager(transport: gated, context: ModelContext(try makeContainer()), validate: nil)
        let service = await DownloadService(
            extractor: PerVideoExtractor(mediaByID: [
                "v23": combinedMedia(videoID: "v23", resolution: 720),
                "v24": combinedMedia(videoID: "v24", resolution: 720)
            ]),
            downloadManager: manager,
            library: try await makeLibrary(),
            mediaDirectory: root.appendingPathComponent("Media")
        )

        let running = Task { await service.download(videoID: "v23", title: "1", channelTitle: "C", quality: .p720) }
        await waitUntil({ service.isInFlight(videoID: "v23", quality: .p720) },
                        "transfer never appeared in flight")

        let queued = Task { await service.download(videoID: "v24", title: "2", channelTitle: "C", quality: .p720) }
        await waitUntil({ [manager] in
            await manager.records.contains { $0.id == "v24-720" && $0.state.status == .queued }
        }, "second download never parked as queued")

        // Cancelling frees a logical slot; the parked request promotes.
        await service.cancel(videoID: "v23", quality: .p720)
        await running.value
        await waitUntil({ [manager] in
            let promoted = await manager.coordinatorTask("v24-720")
            return promoted != nil
        }, "queued download was never promoted after cancel")
        XCTAssertEqual(gated.beginCount, 2)

        gated.release()
        await queued.value
    }

    func testRetryFromFailureListReResolvesFreshComponents() async throws {
        // Mirrors the Downloads failed-list Retry button: re-invoking the
        // service must resolve fresh URLs (not replay expired persisted ones).
        // The completion path needs a real staged temp and an existing
        // destination, mirroring the other finalize-path fixtures.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dsvc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaDirectory = root.appendingPathComponent("Media")
        let destination = mediaDirectory
            .appendingPathComponent("v25")
            .appendingPathComponent("720")
            .appendingPathComponent("media.mp4")
        let temp = root.appendingPathComponent("component.mp4")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01, 0x02]).write(to: temp)
        try Data([0x00]).write(to: destination)

        let switchable = SwitchableTransport(tempLocation: temp)
        let extractor = PerVideoExtractor(mediaByID: [
            "v25": combinedMedia(videoID: "v25", resolution: 720)
        ])
        let manager = DownloadManager(transport: switchable, context: ModelContext(try makeContainer()), validate: nil)
        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: extractor,
            downloadManager: manager,
            library: library,
            mediaDirectory: mediaDirectory
        )

        await service.download(videoID: "v25", title: "Real Title", channelTitle: "Real Channel", quality: .p720)
        var failure = await service.lastFailure
        XCTAssertEqual(failure?.error, .transportFailed)

        // The Retry button path: stored metadata feeds the new request. The
        // failure banner is acknowledged (dismissed) before retrying, so the
        // post-retry assertion below proves the RETRY produced no new failure.
        await service.acknowledgeFailure()
        let metadata = await manager.presentationMetadata(taskID: "v25-720")
        switchable.completeSubsequentTransfers()
        await service.download(
            videoID: "v25",
            title: metadata?.title ?? "v25",
            channelTitle: metadata?.channelTitle ?? "",
            quality: .p720
        )
        failure = await service.lastFailure
        XCTAssertNil(failure)
        // Initial attempt + its one automatic retry + this manual retry: every
        // path re-resolved fresh URLs.
        XCTAssertEqual(extractor.resolveCount(for: "v25"), 3)
        let downloaded = await library.downloaded
        XCTAssertEqual(downloaded.first?.title, "Real Title")
    }

    func testDownloadPersistsPresentationMetadataOnRecord() async throws {
        let manager = DownloadManager(
            transport: FailingTransport(),
            context: ModelContext(try makeContainer()),
            validate: nil
        )
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v26", resolution: 720))),
            downloadManager: manager,
            library: try await makeLibrary()
        )
        await service.download(videoID: "v26", title: "Meta Title", channelTitle: "Meta Channel", quality: .p720)

        let metadata = await manager.presentationMetadata(taskID: "v26-720")
        XCTAssertEqual(metadata?.title, "Meta Title")
        XCTAssertEqual(metadata?.channelTitle, "Meta Channel")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
