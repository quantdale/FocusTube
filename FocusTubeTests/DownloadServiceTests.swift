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

private struct FailingTransport: DownloadTransport {
    func begin(_ request: DownloadRequest, onEvent: @escaping @Sendable (DownloadEvent) -> Void) async {
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
            context: ModelContext(container)
        )
    }

    @MainActor
    private func makeLibrary() throws -> LibraryStore {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return LibraryStore(context: ModelContext(container))
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
                context: ModelContext(try makeContainer())
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
        try Data([0x01, 0x02]).write(to: temp)
        // Pre-create the destination so finalization exercises replaceItemAt's
        // documented existing-destination path (first-download creation is a
        // coordinator/filesystem concern covered elsewhere).
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00]).write(to: destination)

        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v5", resolution: 720))),
            downloadManager: DownloadManager(
                transport: CompletingTransport(tempLocation: temp),
                context: ModelContext(try makeContainer())
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
        try Data([0x01, 0x02]).write(to: temp)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x00]).write(to: destination)

        let library = try await makeLibrary()
        let service = await DownloadService(
            extractor: FakeExtractor(result: .success(combinedMedia(videoID: "v6", resolution: 720))),
            downloadManager: DownloadManager(
                transport: ExpiredThenCompletingTransport(tempLocation: temp),
                context: ModelContext(try makeContainer())
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

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
