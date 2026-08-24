import XCTest
import SwiftData
@testable import FocusTube
import FocusTubeCore

/// DDV2-01: durable queued-download lifecycle. Covers the release-level
/// regression where a capacity-deferred download was persisted `.queued` while
/// its promotion path lived only in process memory — stranding the record,
/// hiding it from the UI, and permanently consuming logical download slots
/// after a relaunch.
@MainActor
final class DurableQueueTests: XCTestCase {
    // MARK: - Fixtures

    /// Gated per-task transport: every begun transfer emits progress and then
    /// waits until its task id is released, completing from a pre-written temp
    /// file so the coordinator's real finalize path runs. Counts begins and
    /// records the requests so tests can assert exactly-once admission, FIFO
    /// promotion order, and that promotions re-resolve instead of replaying
    /// persisted URLs.
    private final class QueueTransport: DownloadTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var released: Set<String> = []
        private var begins: [String: Int] = [:]
        private var begunRequests: [String: DownloadRequest] = [:]
        let tempFiles: [String: URL]

        init(tempFiles: [String: URL]) {
            self.tempFiles = tempFiles
        }

        func beginCount(for taskID: String) -> Int {
            lock.withLock { begins[taskID, default: 0] }
        }

        func begunRequest(for taskID: String) -> DownloadRequest? {
            lock.withLock { begunRequests[taskID] }
        }

        func release(_ taskID: String) {
            lock.withLock { _ = released.insert(taskID) }
        }

        func releaseAll(except keepGated: Set<String> = []) {
            lock.withLock {
                for id in begins.keys where !keepGated.contains(id) {
                    _ = released.insert(id)
                }
            }
        }

        func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
            lock.withLock {
                begins[request.id, default: 0] += 1
                begunRequests[request.id] = request
            }
            onEvent(.progress(component: 0, bytes: 0, total: 100))
            while true {
                let done = lock.withLock { released.contains(request.id) }
                if done { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let temp = tempFiles[request.id] else {
                onEvent(.failed(.unknown))
                return
            }
            onEvent(.completed(tempLocation: temp, component: 0))
        }

        func cancel(taskID: String) async {
            release(taskID)
        }
    }

    private struct PerVideoExtractor: MediaExtracting {
        let mediaByID: [String: ResolvedMedia]
        func resolve(videoID: String) async throws -> ResolvedMedia {
            guard let media = mediaByID[videoID] else { throw ExtractionError.unavailable }
            return media
        }
    }

    private var root: URL!
    private var mediaDirectory: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focustube-dqueue-\(UUID().uuidString)")
        mediaDirectory = root.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        let schema = Schema([DownloadRecord.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func combinedMedia(videoID: String, resolution: Int) -> ResolvedMedia {
        ResolvedMedia(
            videoID: videoID,
            extractedAt: Date(),
            combined: [
                MediaStream(
                    id: "https://media.example/\(videoID)-\(resolution)",
                    videoID: videoID,
                    resolution: resolution,
                    kind: .combined,
                    nativePlayable: true,
                    container: "mp4",
                    videoCodec: "avc1",
                    audioCodec: "mp4a",
                    sourceURL: URL(string: "https://media.example/\(videoID)-\(resolution)")!,
                    expiresAt: nil
                )
            ],
            videoOnly: [],
            audioOnly: []
        )
    }

    /// Pre-creates destination directories and nonzero temp files for each
    /// (video, quality) pair so gated transfers can really complete.
    private func makeFixtures(_ jobs: [(videoID: String, quality: DownloadQuality)]) throws
        -> (transport: QueueTransport, extractor: PerVideoExtractor)
    {
        var temps: [String: URL] = [:]
        var media: [String: ResolvedMedia] = [:]
        for job in jobs {
            let id = "\(job.videoID)-\(job.quality.rawValue)"
            let destination = destinationURL(videoID: job.videoID, quality: job.quality.rawValue)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temp = root.appendingPathComponent("temp-\(id)-\(UUID().uuidString).mp4")
            try Data(count: 128).write(to: temp)
            temps[id] = temp
            media[job.videoID] = combinedMedia(videoID: job.videoID, resolution: job.quality.rawValue)
        }
        return (QueueTransport(tempFiles: temps), PerVideoExtractor(mediaByID: media))
    }

    private func makeManager(transport: DownloadTransport) throws -> DownloadManager {
        DownloadManager(
            transport: transport,
            context: ModelContext(container),
            mediaDirectory: mediaDirectory,
            incompleteDirectory: root.appendingPathComponent("Incomplete"),
            validate: nil
        )
    }

    private func makeService(
        transport: DownloadTransport,
        extractor: MediaExtracting
    ) throws -> (manager: DownloadManager, service: DownloadService, library: LibraryStore) {
        let manager = try makeManager(transport: transport)
        let library = try makeLibrary()
        let service = DownloadService(
            extractor: extractor,
            downloadManager: manager,
            library: library,
            mediaDirectory: mediaDirectory
        )
        // Production wiring lives in AppDependencies; tests replicate it so
        // settlement-driven promotion is exercised exactly as shipped.
        manager.onTaskSettled = { [weak service] _ in
            service?.downloadQueueDidSettle()
        }
        return (manager, service, library)
    }

    private func makeLibrary() throws -> LibraryStore {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let libraryContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return LibraryStore(context: ModelContext(libraryContainer))
    }

    private func destinationURL(videoID: String, quality: Int) -> URL {
        mediaDirectory
            .appendingPathComponent(videoID)
            .appendingPathComponent("\(quality)")
            .appendingPathComponent("media.mp4")
    }

    /// Polls until the condition holds or the timeout elapses.
    private func waitUntil(
        _ condition: () async -> Bool,
        timeout: TimeInterval = 5,
        _ message: @autoclosure () -> String
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message())
    }

    private func fetchRecord(_ taskID: String, context: ModelContext) throws -> DownloadRecord? {
        try context.fetch(FetchDescriptor<DownloadRecord>()).first(where: { $0.id == taskID })
    }

    /// Starts two gated transfers (both slots busy).
    private func startTwoActiveJobs(
        _ service: DownloadService,
        transport: QueueTransport
    ) async {
        Task { await service.download(videoID: "v1", title: "One", channelTitle: "C", quality: .p720) }
        Task { await service.download(videoID: "v2", title: "Two", channelTitle: "C", quality: .p720) }
        await waitUntil({ transport.beginCount(for: "v1-720") == 1 }, "first transfer should begin")
        await waitUntil({ transport.beginCount(for: "v2-720") == 1 }, "second transfer should begin")
    }

    // MARK: - In-session queue behavior

    func testThirdRequestDefersToDurableQueuedRecordWithoutTransferOrSignedURLs() async throws {
        let (transport, extractor) = try makeFixtures([
            ("v1", .p720), ("v2", .p720), ("v3", .p480)
        ])
        let (_, service, _) = try makeService(transport: transport, extractor: extractor)
        defer { transport.releaseAll() }

        await startTwoActiveJobs(service, transport: transport)

        // Third request finds the budget exhausted: it must return promptly
        // (persisted `.queued`, no transfer started).
        await service.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)

        let context = ModelContext(container)
        let queuedRow = try XCTUnwrap(fetchRecord("v3-480", context: context))
        XCTAssertEqual(queuedRow.statusRaw, DownloadStatus.queued.rawValue)
        XCTAssertEqual(queuedRow.queuedMetadata?.title, "Three")
        XCTAssertEqual(queuedRow.queuedMetadata?.channelTitle, "C")
        XCTAssertEqual(queuedRow.resolution, 480)
        // Ephemeral signed URLs must NOT be persisted as an authoritative
        // retry source: queued rows carry no components at all.
        XCTAssertTrue(queuedRow.components.isEmpty)
        XCTAssertNil(await service.downloadManager.coordinatorTask("v3-480"))
        XCTAssertEqual(transport.beginCount(for: "v3-480"), 0)
        XCTAssertEqual(service.downloadManager.queuedTasks.map(\.id), ["v3-480"])
    }

    func testSettlePromotesOldestQueuedJobFirstAndExactlyOnce() async throws {
        let (transport, extractor) = try makeFixtures([
            ("v1", .p720), ("v2", .p720), ("v3", .p480), ("v4", .p360)
        ])
        let (_, service, _) = try makeService(transport: transport, extractor: extractor)
        defer { transport.releaseAll() }

        await startTwoActiveJobs(service, transport: transport)
        await service.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)
        await service.download(videoID: "v4", title: "Four", channelTitle: "C", quality: .p360)

        // Completing v1 frees exactly one slot: v3 (oldest) promotes, v4 stays.
        transport.release("v1-720")
        await waitUntil({ transport.beginCount(for: "v3-480") == 1 }, "oldest queued job should be promoted")
        XCTAssertEqual(transport.beginCount(for: "v4-360"), 0, "younger queued job must not overtake FIFO")
        XCTAssertEqual(service.downloadManager.queuedTasks.map(\.id), ["v4-360"])

        // Completing v2 frees the next slot: v4 follows.
        transport.release("v2-720")
        await waitUntil({ transport.beginCount(for: "v4-360") == 1 }, "remaining queued job should be promoted")

        // Drain everything and confirm clean terminal state.
        transport.release("v3-480")
        transport.release("v4-360")
        await waitUntil(
            { [weak manager = service.downloadManager] in
                (manager?.liveTasks.isEmpty ?? false)
                    && (manager?.queuedTasks.isEmpty ?? false)
                    && (manager?.failedTasks.isEmpty ?? false)
            },
            "all transfers should settle"
        )
        let downloaded = await service.library.downloaded
        XCTAssertEqual(Set(downloaded.map(\.id)), ["v1-720", "v2-720", "v3-480", "v4-360"])
        // Exact requested qualities preserved end-to-end.
        XCTAssertTrue(downloaded.allSatisfy { item in
            switch item.id {
            case "v1-720", "v2-720": return item.resolution == 720
            case "v3-480": return item.resolution == 480
            case "v4-360": return item.resolution == 360
            default: return false
            }
        })
    }

    func testDuplicateAdmissionRemainsImpossibleWhilePromotedJobRuns() async throws {
        let (transport, extractor) = try makeFixtures([
            ("v1", .p720), ("v2", .p720), ("v3", .p480)
        ])
        let (_, service, _) = try makeService(transport: transport, extractor: extractor)
        defer { transport.releaseAll() }

        await startTwoActiveJobs(service, transport: transport)
        await service.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)
        transport.release("v1-720")
        await waitUntil({ transport.beginCount(for: "v3-480") == 1 }, "promotion should start the transfer")

        // A second start for the same video+quality while the promoted job is
        // live must be rejected by the synchronous admission reservation.
        await service.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(transport.beginCount(for: "v3-480"), 1, "duplicate transfer must never begin")
    }

    func testCancellingAQueuedJobDeletesRecordAndPreservesFIFForRemaining() async throws {
        let (transport, extractor) = try makeFixtures([
            ("v1", .p720), ("v2", .p720), ("v3", .p480), ("v4", .p360)
        ])
        let (_, service, _) = try makeService(transport: transport, extractor: extractor)
        defer { transport.releaseAll() }

        await startTwoActiveJobs(service, transport: transport)
        await service.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)
        await service.download(videoID: "v4", title: "Four", channelTitle: "C", quality: .p360)

        // Cancelling the QUEUED head deletes its durable record entirely.
        await service.cancel(videoID: "v3", quality: .p480)
        let context = ModelContext(container)
        XCTAssertNil(try fetchRecord("v3-480", context: context), "cancelled queue intention must not linger")
        XCTAssertEqual(service.downloadManager.queuedTasks.map(\.id), ["v4-360"])

        transport.release("v1-720")
        await waitUntil({ transport.beginCount(for: "v4-360") == 1 }, "next surviving queued job should promote")
        XCTAssertEqual(transport.beginCount(for: "v3-480"), 0, "cancelled job must never be promoted")
    }

    // MARK: - Process recreation (relaunch)

    func testRelaunchReconstructsQueueFromPersistedRecordsAndDrainsWithinBudget() async throws {
        let (transportA, extractorA) = try makeFixtures([
            ("v1", .p720), ("v2", .p720), ("v3", .p480), ("v4", .p360)
        ])
        let (_, serviceA, _) = try makeService(transport: transportA, extractor: extractorA)

        await startTwoActiveJobs(serviceA, transport: transportA)
        await serviceA.download(videoID: "v3", title: "Three", channelTitle: "C", quality: .p480)
        await serviceA.download(videoID: "v4", title: "Four", channelTitle: "C", quality: .p360)
        XCTAssertEqual(serviceA.downloadManager.queuedTasks.map(\.id), ["v3-480", "v4-360"])

        // --- simulated process death & recreation over the SAME store ---
        let (transportB, extractorB) = try makeFixtures([("v3", .p480), ("v4", .p360)])
        let (managerB, serviceB, libraryB) = try makeService(transport: transportB, extractor: extractorB)

        await serviceB.restorePersistedQueue()

        // The previous actives did not survive (no background recovery in this
        // fake): they reconcile to typed interrupted failures, freeing slots.
        XCTAssertEqual(managerB.failedTasks.map(\.id).sorted(), ["v1-720", "v2-720"])
        // The persisted queue was reconstructed and immediately drained into
        // the freed budget — without waiting for any unrelated settle event.
        await waitUntil({ transportB.beginCount(for: "v3-480") == 1 }, "restored queue should resume")
        await waitUntil({ transportB.beginCount(for: "v4-360") == 1 }, "restored queue should fill the budget")
        XCTAssertEqual(managerB.queuedTasks.map(\.id), [], "queue should have drained into active slots")

        // Exact requested qualities survive reconstruction.
        XCTAssertEqual(transportB.begunRequest(for: "v3-480")?.resolution, 480)
        XCTAssertEqual(transportB.begunRequest(for: "v4-360")?.resolution, 360)

        transportB.release("v3-480")
        transportB.release("v4-360")
        await waitUntil(
            { managerB.liveTasks.isEmpty && managerB.queuedTasks.isEmpty },
            "restored transfers should settle"
        )
        let downloaded = await libraryB.downloaded
        XCTAssertEqual(Set(downloaded.map(\.id)), ["v3-480", "v4-360"])
        XCTAssertEqual(downloaded.first(where: { $0.id == "v3-480" })?.title, "Three")
        XCTAssertEqual(downloaded.first(where: { $0.id == "v4-360" })?.title, "Four")
        transportA.releaseAll()
    }

    func testLegacyQueuedRowWithoutMetadataRestoresFromRowFields() async throws {
        // Seed a pre-DDV2 legacy row: `.queued`, presentation fields absent,
        // component list carrying an (already meaningless) signed URL.
        let legacyDestination = destinationURL(videoID: "L1", quality: 720)
        try FileManager.default.createDirectory(
            at: legacyDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let context = ModelContext(container)
        let legacyTask = DownloadTask(
            id: "L1-720",
            videoID: "L1",
            resolution: 720,
            destinationURL: legacyDestination,
            components: [DownloadComponent(
                streamID: "legacy-stream",
                sourceURL: URL(string: "https://signed.example/expired?fingerprint=zzz")!
            )],
            state: DownloadState(status: .queued)
        )
        context.insert(DownloadRecord(task: legacyTask))
        try context.save()

        // Recreation: legacy row must synthesize its queue payload from the
        // row fields and promote through a FRESH extraction (never replaying
        // the persisted URL).
        let (transportB, extractorB) = try makeFixtures([("L1", .p720)])
        let (managerB, serviceB, libraryB) = try makeService(transport: transportB, extractor: extractorB)
        defer { transportB.releaseAll() }

        await serviceB.restorePersistedQueue()

        await waitUntil({ transportB.beginCount(for: "L1-720") == 1 }, "legacy queued row should promote")
        let request = try XCTUnwrap(transportB.begunRequest(for: "L1-720"))
        XCTAssertNotEqual(
            request.components.first?.sourceURL.host,
            "signed.example",
            "promotion must re-resolve, not replay the legacy signed URL"
        )

        transportB.release("L1-720")
        await waitUntil({ managerB.liveTasks.isEmpty }, "legacy transfer should settle")
        let downloaded = await libraryB.downloaded
        XCTAssertEqual(downloaded.first(where: { $0.id == "L1-720" })?.title, "L1")
    }

    func testCorruptedQueuedRecordDegradesToRecoverableFailureWithoutDeadlock() async throws {
        // Seed an unusable queued row: invalid video id alphabet and a
        // resolution outside the allowed ladder.
        let context = ModelContext(container)
        let corruptTask = DownloadTask(
            id: "bad-999",
            videoID: "../evil",
            resolution: 999,
            destinationURL: mediaDirectory.appendingPathComponent("whatever"),
            components: [],
            state: DownloadState(status: .queued)
        )
        context.insert(DownloadRecord(task: corruptTask))
        try context.save()

        let (transportB, extractorB) = try makeFixtures([("fresh", .p720)])
        let (managerB, serviceB, _) = try makeService(transport: transportB, extractor: extractorB)
        defer { transportB.releaseAll() }

        await serviceB.restorePersistedQueue()

        // Degraded to a typed, actionable failure — not stranded as queued.
        let degraded = try XCTUnwrap(fetchRecord("bad-999", context: ModelContext(container)))
        XCTAssertEqual(degraded.statusRaw, DownloadStatus.failed.rawValue)
        XCTAssertEqual(degraded.errorRaw, DownloadError.queueStateCorrupted.rawValue)
        XCTAssertEqual(managerB.failedTasks.map(\.id), ["bad-999"])
        XCTAssertTrue(managerB.queuedTasks.isEmpty)
        // And crucially: it consumes NO logical slot — new work admits freely.
        Task { await serviceB.download(videoID: "fresh", title: "Fresh", channelTitle: "C", quality: .p720) }
        await waitUntil({ transportB.beginCount(for: "fresh-720") == 1 }, "admission must not deadlock")
    }

    func testCorruptedQueueFailureCarriesActionableUserCopy() {
        let failure = DownloadFailure(
            videoID: "x", title: "T", quality: .p480, error: .queueStateCorrupted
        )
        XCTAssertFalse(failure.userMessage.isEmpty)
        XCTAssertTrue(failure.userMessage.lowercased().contains("again"), failure.userMessage)
    }
}
