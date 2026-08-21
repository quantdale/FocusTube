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
                LibraryView(store: libraryStore)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .task {
            // The coordinator is created once in init; re-appearance only
            // re-configures the session and re-registers (idempotent) commands.
            try? backgroundMedia.configureAudioSession()
            backgroundMedia.registerRemoteCommands()
            backgroundMedia.registerInterruptionObservation()
        }
    }
}

struct DownloadsView: View {
    let store: LibraryStore
    @Bindable var downloadManager: DownloadManager
    let downloadService: DownloadService
    let playerCoordinator: PlayerCoordinator

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
                            Text(task.videoID).font(.subheadline).lineLimit(1)
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
                        }
                    }
                }
            }

            Section("Downloaded") {
                ForEach(store.downloaded, id: \.id) { item in
                    HStack {
                        Button {
                            playerCoordinator.playLocalFile(item.fileURL)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).lineLimit(2)
                                Text("\(item.resolution)p · \(item.sizeBytes) bytes").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.deleteDownloadedMedia(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                if store.downloaded.isEmpty {
                    Text("No downloaded videos yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Downloads")
        .task { store.reconcileDownloads() }
    }
}

struct LibraryView: View {
    let store: LibraryStore

    var body: some View {
        List {
            Section("Continue watching") {
                ForEach(store.history, id: \.videoID) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).lineLimit(2)
                        Text(entry.channelTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Saved") {
                ForEach(store.saved, id: \.videoID) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(2)
                        Text(item.channelTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Library")
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
            Button {
                Task { await store.loadMore() }
            } label: {
                Label("Load more", systemImage: "arrow.down.circle")
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
