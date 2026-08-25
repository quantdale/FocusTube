import SwiftUI
import FocusTubeCore

/// Downloads surface (DDV2-02): active queue with human-readable phases and
/// progress, the durable queued section, typed failures with retry, and an
/// offline library with sorting, channel grouping, and total storage usage.
/// Pause/resume is deliberately absent: background `URLSession` download tasks
/// cannot resume reliably across process death, so cancel + retry is provided
/// instead of a fake pause control (documented in docs/03).
struct DownloadsView: View {
    let store: LibraryStore
    @Bindable var downloadManager: DownloadManager
    let downloadService: DownloadService
    let playerCoordinator: PlayerCoordinator

    @State private var pendingDelete: DownloadedMedia?
    @State private var sortOrder: OfflineLibraryPolicy.SortOrder = .newestFirst
    @State private var playingLocal: OfflineMediaSummary?

    /// Phases the coordinator's state machine allows cancelling. Validating/
    /// muxing/finalizing are intentionally non-cancellable — the coordinator
    /// rejects cancel transitions out of those phases so a final file is never
    /// corrupted mid-write — so the row button hides for them.
    private static let cancellableStatuses: Set<DownloadStatus> = [
        .queued, .downloading, .paused, .waitingForRetry, .reResolving
    ]

    var body: some View {
        // A deliberate non-lazy scroll view: personal-scale download counts make
        // laziness worthless here, while lazy List rows proved unreliable to
        // realize in both the accessibility tree and XCUITest queries on current
        // iOS runtimes (the same contract as VideoPageView).
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                activeSection
                queuedSection
                failedSection
                offlineHeaderSection
                offlineContentSections
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Downloads")
        .sheet(item: $playingLocal) { media in
            LocalPlayerSheet(playerCoordinator: playerCoordinator, media: media) {
                playingLocal = nil
            }
        }
        .confirmationDialog(
            "Delete downloaded video?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { media in
            Button("Delete", role: .destructive) {
                store.deleteDownloadedMedia(id: media.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("The downloaded file will be removed from this device.")
        }
        .task { store.reconcileDownloads() }
    }

    // MARK: - Section scaffolding

    /// Non-List section container with an accessible header so every row is
    /// always realized in the hierarchy (never lazily discarded).
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func emptyText(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Active queue

    private var activeSection: some View {
        section("In progress") {
            if downloadManager.liveTasks.isEmpty {
                emptyText("No active downloads.")
            }
            ForEach(downloadManager.liveTasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(downloadManager.presentationMetadata(taskID: task.id)?.title ?? task.videoID)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(task.resolution)p · \(Self.phaseLabel(task.state.status))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        progressRow(task.state)
                    }
                    Spacer()
                    if Self.cancellableStatuses.contains(task.state.status),
                       let quality = DownloadQuality(rawValue: task.resolution) {
                        Button(role: .destructive) {
                            Task {
                                await downloadService.cancel(videoID: task.videoID, quality: quality)
                            }
                        } label: {
                            Image(systemName: "stop.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Cancel download")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func progressRow(_ state: DownloadState) -> some View {
        if state.totalBytes > 0 {
            ProgressView(value: Double(state.bytesDownloaded), total: Double(state.totalBytes))
            Text("\(Self.progressPercent(state)) · \(OfflineLibraryPolicy.formattedFileSize(state.bytesDownloaded)) of \(OfflineLibraryPolicy.formattedFileSize(state.totalBytes))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    // MARK: - Durable queue

    private var queuedSection: some View {
        section("Waiting to download") {
            // Durable queue projection (DDV2-01): persisted `.queued`
            // records are user-visible and cancellable, never invisible
            // slot consumers.
            if downloadManager.queuedTasks.isEmpty {
                emptyText("Nothing waiting.")
            }
            ForEach(downloadManager.queuedTasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(downloadManager.presentationMetadata(taskID: task.id)?.title ?? task.videoID)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("\(task.resolution)p · \(Self.phaseLabel(task.state.status))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let quality = DownloadQuality(rawValue: task.resolution) {
                        Button(role: .destructive) {
                            Task {
                                await downloadService.cancel(videoID: task.videoID, quality: quality)
                            }
                        } label: {
                            Image(systemName: "stop.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Cancel download")
                    }
                }
            }
        }
    }

    // MARK: - Failures

    private var failedSection: some View {
        section("Failed downloads") {
            // Failed/interrupted records stay listed so the promised retry
            // is actionable: Retry re-invokes the service, which re-resolves
            // fresh signed URLs instead of replaying expired ones. Served
            // from the cached failure projection (HB-013), not a per-render
            // SwiftData refetch.
            if downloadManager.failedTasks.isEmpty {
                emptyText("No failed downloads.")
            }
            ForEach(downloadManager.failedTasks) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(downloadManager.presentationMetadata(taskID: task.id)?.title ?? task.videoID)
                            .lineLimit(2)
                        Text("\(task.resolution)p · \(task.state.error?.rawValue ?? Self.phaseLabel(task.state.status))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let quality = DownloadQuality(rawValue: task.resolution) {
                        let metadata = downloadManager.presentationMetadata(taskID: task.id)
                        Button("Retry") {
                            Task {
                                await downloadService.download(
                                    videoID: task.videoID,
                                    title: metadata?.title ?? task.videoID,
                                    channelTitle: metadata?.channelTitle ?? "",
                                    quality: quality
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offline library

    private var offlineSummaries: [OfflineMediaSummary] {
        store.downloaded.map { media in
            OfflineMediaSummary(
                id: media.id,
                title: media.title,
                channelTitle: media.channelTitle ?? "",
                resolution: media.resolution,
                sizeBytes: media.sizeBytes,
                createdAt: media.createdAt
            )
        }
    }

    private var offlineHeaderSection: some View {
        section("Downloaded") {
            Picker("Sort by", selection: $sortOrder) {
                Text("Newest").tag(OfflineLibraryPolicy.SortOrder.newestFirst)
                Text("Largest").tag(OfflineLibraryPolicy.SortOrder.largestFirst)
                Text("Channel").tag(OfflineLibraryPolicy.SortOrder.byChannelThenNewest)
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("downloads-sort-picker")

            let summaries = offlineSummaries
            let total = OfflineLibraryPolicy.totalBytes(summaries)
            Text("Offline storage: \(OfflineLibraryPolicy.formattedFileSize(total)) · \(summaries.count) video\(summaries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("offline-storage-summary")

            if summaries.isEmpty {
                emptyText("No downloaded videos yet.")
            }
        }
    }

    @ViewBuilder
    private var offlineContentSections: some View {
        let summaries = offlineSummaries
        switch sortOrder {
        case .byChannelThenNewest:
            ForEach(OfflineLibraryPolicy.groupedByChannel(summaries), id: \.channel) { group in
                section(group.channel) {
                    ForEach(group.items, id: \.id) { item in
                        offlineRow(item)
                    }
                }
            }
        default:
            if !summaries.isEmpty {
                section("Offline videos") {
                    ForEach(OfflineLibraryPolicy.sorted(summaries, by: sortOrder), id: \.id) { item in
                        offlineRow(item)
                    }
                }
            }
        }
    }

    private func offlineRow(_ item: OfflineMediaSummary) -> some View {
        HStack {
            Button {
                // Local playback must not tick the online video page's
                // history handler; route progress away and set local Now
                // Playing metadata explicitly. A visible local player surface
                // (HB-014) lets journeys assert a genuine playing state.
                playerCoordinator.onProgress = nil
                if let stored = store.downloaded.first(where: { $0.id == item.id }) {
                    playerCoordinator.playLocalFile(
                        stored.fileURL,
                        title: item.title,
                        artist: nil
                    )
                    playingLocal = item
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .lineLimit(2)
                        .accessibilityIdentifier("downloaded-row-title")
                    Text("\(item.resolution)p · \(OfflineLibraryPolicy.formattedFileSize(item.sizeBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("downloaded-row")
            Spacer()
            Button(role: .destructive) {
                pendingDelete = store.downloaded.first(where: { $0.id == item.id })
            } label: {
                Image(systemName: "trash")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Delete download")
        }
    }

    // MARK: - Copy helpers

    /// Human-readable phase names — raw enum values never render (docs/12).
    static func phaseLabel(_ status: DownloadStatus) -> String {
        switch status {
        case .idle: return "Idle"
        case .queued: return "Queued"
        case .resolving: return "Resolving"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .validating: return "Validating"
        case .muxing: return "Combining tracks"
        case .finalizing: return "Finishing"
        case .waitingForRetry: return "Retrying"
        case .reResolving: return "Refreshing link"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    static func progressPercent(_ state: DownloadState) -> String {
        guard state.totalBytes > 0 else { return "" }
        let fraction = min(1, Double(state.bytesDownloaded) / Double(state.totalBytes))
        return "\(Int((fraction * 100).rounded()))%"
    }
}

/// Full-screen local player for offline media. Stopping on dismiss prevents
/// background audio continuing invisibly after the surface is gone.
struct LocalPlayerSheet: View {
    let playerCoordinator: PlayerCoordinator
    let media: OfflineMediaSummary
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            PlayerView(coordinator: playerCoordinator)
                .padding(.top, 48)
            VStack {
                HStack {
                    Text(media.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button("Done") {
                        playerCoordinator.stop()
                        onDone()
                    }
                    .accessibilityIdentifier("local-player-done")
                }
                .padding(.horizontal)
                .padding(.top, 8)
                Spacer()
            }
        }
    }
}
