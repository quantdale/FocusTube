import SwiftUI
import SwiftData
import os
import FocusTubeCore

struct RootView: View {
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "app-shell")

    @State private var playerCoordinator: PlayerCoordinator
    @State private var homeStore = HomeFeedStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var searchStore = SearchStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var auth: AuthSession = GoogleSignInAuthSession()
    @State private var api: YouTubeAPI = YouTubeDataClient()
    @State private var libraryStore: LibraryStore
    @State private var downloadManager: DownloadManager
    @State private var downloadService: DownloadService
    @State private var backgroundMedia: BackgroundMediaCoordinator

    init() {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self, DownloadRecord.self])
        // Resilience over durability: a corrupted/unopenable store must not crash
        // the app at launch, so fall back to an in-memory container (personal-use
        // tradeoff: library metadata then lasts only this session). The fallback
        // force-try cannot fail for disk reasons — in-memory storage does no I/O.
        let container: ModelContainer
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            Self.logger.fault("Persistent ModelContainer failed to open (\(error.localizedDescription, privacy: .public)); using in-memory store")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
        let library = LibraryStore(context: ModelContext(container))
        let manager = DownloadManager(transport: BackgroundDownloadTransport.shared, context: ModelContext(container))
        // Transfers that finish via the relaunched background session bypass
        // DownloadService; register them so offline media is never orphaned.
        // The library upserts by id, so this stays idempotent with in-app
        // registration.
        manager.onMediaFinalized = { [library] task in
            let size = (try? task.destinationURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            library.addDownloadedMedia(DownloadedMedia(
                id: task.id,
                videoID: task.videoID,
                title: task.videoID,
                resolution: task.resolution,
                fileURL: task.destinationURL,
                sizeBytes: Int64(size),
                createdAt: Date()
            ))
        }
        let player = PlayerCoordinator()
        _libraryStore = State(initialValue: library)
        _downloadManager = State(initialValue: manager)
        _downloadService = State(initialValue: DownloadService(downloadManager: manager, library: library))
        _playerCoordinator = State(initialValue: player)
        _backgroundMedia = State(initialValue: BackgroundMediaCoordinator(target: player))
    }

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
        }
    }
}

struct DownloadsView: View {
    let store: LibraryStore
    @Bindable var downloadManager: DownloadManager
    let playerCoordinator: PlayerCoordinator

    var body: some View {
        List {
            Section("Downloads in progress") {
                if downloadManager.liveTasks.isEmpty {
                    Text("No active downloads.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloadManager.liveTasks) { task in
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
