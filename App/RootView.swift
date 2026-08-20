import SwiftUI
import SwiftData
import FocusTubeCore

struct RootView: View {
    @State private var playerCoordinator = PlayerCoordinator()
    @State private var homeStore = HomeFeedStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var searchStore = SearchStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var auth: AuthSession = GoogleSignInAuthSession()
    @State private var api: YouTubeAPI = YouTubeDataClient()
    @State private var libraryStore: LibraryStore
    @State private var downloadManager: DownloadManager
    @State private var downloadService: DownloadService
    @State private var backgroundMedia: BackgroundMediaCoordinator? = nil

    init() {
        let schema = Schema([WatchHistoryEntry.self, SavedItem.self, DownloadedMedia.self, DownloadRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let library = LibraryStore(context: ModelContext(container))
        let manager = DownloadManager(transport: URLSessionDownloadTransport(), context: ModelContext(container))
        _libraryStore = State(initialValue: library)
        _downloadManager = State(initialValue: manager)
        _downloadService = State(initialValue: DownloadService(downloadManager: manager, library: library))
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
                DownloadsView(store: libraryStore, playerCoordinator: playerCoordinator)
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            NavigationStack {
                LibraryView(store: libraryStore)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .task {
            let coordinator = BackgroundMediaCoordinator(target: playerCoordinator)
            backgroundMedia = coordinator
            try? coordinator.configureAudioSession()
            coordinator.registerRemoteCommands()
        }
    }
}

private struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "play.rectangle", description: Text(message))
            .navigationTitle(title)
    }
}

struct DownloadsView: View {
    @Bindable var store: LibraryStore
    let playerCoordinator: PlayerCoordinator

    var body: some View {
        List {
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
        .navigationTitle("Downloads")
        .task { store.reconcileDownloads() }
    }
}

struct LibraryView: View {
    @Bindable var store: LibraryStore

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
            Button {
                selectedVideo = VideoSummary(id: "aqz-KE-bpKQ", title: "Big Buck Bunny", channelTitle: "Demo", durationSeconds: nil, publishedAt: nil, thumbnailURL: nil, description: nil)
                showVideo = true
            } label: {
                Label("Open native player (M1 demo)", systemImage: "play.circle")
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
