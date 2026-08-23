import SwiftUI
import os
import FocusTubeCore

struct RootView: View {
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "app-shell")

    let dependencies: AppDependencies

    @State private var homeStore = HomeFeedStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var searchStore = SearchStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var auth: AuthSession = GoogleSignInAuthSession()
    @State private var api: YouTubeAPI = YouTubeDataClient()

    // Long-lived dependencies are owned by AppDependencies (created once per
    // process); these accessors keep the body below readable.
    private var playerCoordinator: PlayerCoordinator { dependencies.playerCoordinator }
    private var libraryStore: LibraryStore { dependencies.libraryStore }
    private var downloadManager: DownloadManager { dependencies.downloadManager }
    private var downloadService: DownloadService { dependencies.downloadService }
    private var backgroundMedia: BackgroundMediaCoordinator { dependencies.backgroundMedia }

    var body: some View {
        TabView {
            NavigationStack {
                HomeFeedView(
                    store: homeStore,
                    playerCoordinator: playerCoordinator,
                    auth: auth,
                    api: api,
                    downloadService: downloadService,
                    library: libraryStore
                )
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                SearchView(
                    store: searchStore,
                    playerCoordinator: playerCoordinator,
                    auth: auth,
                    api: api,
                    downloadService: downloadService,
                    library: libraryStore
                )
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                DownloadsView(
                    store: libraryStore,
                    downloadManager: downloadManager,
                    downloadService: downloadService,
                    playerCoordinator: playerCoordinator
                )
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            NavigationStack {
                LibraryView(
                    store: libraryStore,
                    playerCoordinator: playerCoordinator,
                    auth: auth,
                    api: api,
                    downloadService: downloadService
                )
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .task {
            // The coordinator is created once in init; re-appearance only
            // re-configures the session and re-registers (idempotent) commands.
            try? backgroundMedia.configureAudioSession()
            backgroundMedia.registerRemoteCommands()
            backgroundMedia.registerInterruptionObservation()
            backgroundMedia.registerRouteChangeObservation()
        }
    }
}

struct DownloadsView: View {
    let store: LibraryStore
    @Bindable var downloadManager: DownloadManager
    let downloadService: DownloadService
    let playerCoordinator: PlayerCoordinator

    @State private var pendingDelete: DownloadedMedia?

    /// Phases the coordinator's state machine allows cancelling. Validating/
    /// muxing/finalizing are intentionally non-cancellable — the coordinator
    /// rejects cancel transitions out of those phases so a final file is never
    /// corrupted mid-write — so the row button hides for them.
    private static let cancellableStatuses: Set<DownloadStatus> = [
        .queued, .downloading, .paused, .waitingForRetry, .reResolving
    ]

    var body: some View {
        List {
            Section("Downloads in progress") {
                if downloadManager.liveTasks.isEmpty {
                    Text("No active downloads.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloadManager.liveTasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                downloadManager.presentationMetadata(taskID: task.id)?.title
                                    ?? task.videoID
                            )
                            .font(.subheadline)
                            .lineLimit(1)
                            Text("\(task.resolution)p · \(task.state.status.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if task.state.totalBytes > 0 {
                                ProgressView(value: Double(task.state.bytesDownloaded), total: Double(task.state.totalBytes))
                            } else {
                                ProgressView()
                            }
                        }
                        Spacer()
                        if Self.cancellableStatuses.contains(task.state.status),
                           let quality = DownloadQuality(rawValue: task.resolution) {
                            Button(role: .destructive) {
                                Task {
                                    await downloadService.cancel(
                                        videoID: task.videoID,
                                        quality: quality
                                    )
                                }
                            } label: {
                                Image(systemName: "stop.fill")
                            }
                            .accessibilityLabel("Cancel download")
                        }
                    }
                }
            }

            Section("Failed downloads") {
                // Failed/interrupted records stay listed so the promised retry
                // is actionable: Retry re-invokes the service, which re-resolves
                // fresh signed URLs instead of replaying expired ones.
                let failed = downloadManager.records.filter { $0.state.status == .failed }
                if failed.isEmpty {
                    Text("No failed downloads.")
                        .foregroundStyle(.secondary)
                }
                ForEach(failed) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(downloadManager.presentationMetadata(taskID: task.id)?.title ?? task.videoID)
                                .lineLimit(2)
                            Text("\(task.resolution)p · \(task.state.error?.rawValue ?? task.state.status.rawValue)")
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

            Section("Downloaded") {
                ForEach(store.downloaded, id: \.id) { item in
                    HStack {
                        Button {
                            // Local playback must not tick the online video
                            // page's history handler; route progress away and
                            // set local Now Playing metadata explicitly.
                            playerCoordinator.onProgress = nil
                            playerCoordinator.playLocalFile(
                                item.fileURL,
                                title: item.title,
                                artist: nil
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).lineLimit(2)
                                Text("\(item.resolution)p · \(item.sizeBytes) bytes").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDelete = item
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete download")
                    }
                }
                if store.downloaded.isEmpty {
                    Text("No downloaded videos yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Downloads")
        .confirmationDialog(
            "Delete downloaded video?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete,
            titleVisibility: .visible
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
}

struct LibraryView: View {
    let store: LibraryStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService

    @State private var selectedSummary: VideoSummary?
    @State private var showVideo = false

    var body: some View {
        List {
            Section("Continue watching") {
                let inProgress = store.history.filter { !$0.completed }
                if inProgress.isEmpty {
                    Text("Nothing in progress.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inProgress, id: \.videoID) { entry in
                    Button {
                        open(Self.summary(from: entry))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).lineLimit(2)
                            Text(entry.channelTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Opens the video and resumes where you left off")
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.removeHistory(videoID: inProgress[index].videoID)
                    }
                }
            }
            Section("Saved") {
                if store.saved.isEmpty {
                    Text("No saved videos yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.saved, id: \.videoID) { item in
                    Button {
                        open(Self.summary(from: item))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).lineLimit(2)
                            Text(item.channelTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Opens the saved video")
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.removeSaved(videoID: store.saved[index].videoID)
                    }
                }
            }
        }
        .navigationTitle("Library")
        .sheet(isPresented: $showVideo) {
            if let summary = selectedSummary {
                NavigationStack {
                    VideoPageView(
                        video: summary,
                        coordinator: playerCoordinator,
                        auth: auth,
                        api: api,
                        downloadService: downloadService,
                        library: store
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showVideo = false }
                        }
                    }
                }
            }
        }
    }

    private func open(_ summary: VideoSummary) {
        selectedSummary = summary
        showVideo = true
    }

    /// Rebuilds the navigation payload from persisted fields; optional API-only
    /// attributes (thumbnail/publish date/description) are not stored locally.
    private static func summary(from entry: WatchHistoryEntry) -> VideoSummary {
        VideoSummary(
            id: entry.videoID,
            title: entry.title,
            channelTitle: entry.channelTitle,
            durationSeconds: entry.durationSeconds,
            publishedAt: nil,
            thumbnailURL: nil,
            description: nil
        )
    }

    private static func summary(from item: SavedItem) -> VideoSummary {
        VideoSummary(
            id: item.videoID,
            title: item.title,
            channelTitle: item.channelTitle,
            durationSeconds: nil,
            publishedAt: nil,
            thumbnailURL: nil,
            description: nil
        )
    }
}

/// Chronological long-form subscription Home feed with the short-form firewall
/// applied before render. Load-more is an explicit user action.
private struct HomeFeedView: View {
    @Bindable var store: HomeFeedStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService
    let library: LibraryStore

    @State private var showVideo = false
    @State private var selectedVideo: VideoSummary?

    var body: some View {
        List {
            if !store.isAuthenticated, store.videos.isEmpty, !store.isLoading {
                // Fresh install: GoogleSignIn is restore-only until the user
                // explicitly signs in. Hidden for fake sessions (tests) and
                // once authenticated.
                Button {
                    Task {
                        if await (auth as? GoogleSignInAuthSession)?.signIn() == true {
                            await store.restore()
                            await store.load()
                        }
                    }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            if store.isLoading {
                ProgressView("Loading feed…")
            }
            ForEach(store.videos) { video in
                Button {
                    selectedVideo = video
                    showVideo = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title).lineLimit(2)
                        Text(video.channelTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.nextPageToken != nil {
                Button {
                    Task { await store.loadMore() }
                } label: {
                    Label("Load more", systemImage: "arrow.down.circle")
                }
            }
        }
        .navigationTitle("Home")
        .task {
            await store.restore()
            await store.load()
        }
        .sheet(isPresented: $showVideo) {
            if let video = selectedVideo {
                NavigationStack {
                    VideoPageView(
                        video: video,
                        coordinator: playerCoordinator,
                        auth: auth,
                        api: api,
                        downloadService: downloadService,
                        library: library
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showVideo = false }
                        }
                    }
                }
            }
        }
    }
}
