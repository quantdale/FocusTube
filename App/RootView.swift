import SwiftUI
import os
import FocusTubeCore

/// ADR-0008 shell: Home (local subscriptions feed), Add (paste a link + local
/// search; replaces Search) and Library. No sign-in.
struct RootView: View {
    let dependencies: AppDependencies

    private var playerCoordinator: PlayerCoordinator { dependencies.playerCoordinator }
    private var libraryStore: LibraryStore { dependencies.libraryStore }
    private var localLibrary: LocalLibraryModel { dependencies.localLibrary }
    private var backgroundMedia: BackgroundMediaCoordinator { dependencies.backgroundMedia }

    /// HB-029: explicit tab selection persisted across scene restoration.
    @SceneStorage("FocusTube.selectedTab") private var selectedTab = 0
    @State private var homeVideo: VideoSummary?
    @State private var addVideo: VideoSummary?
    @State private var addPlaylist: SavedPlaylist?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SubscriptionsFeedView(
                    model: localLibrary,
                    resumeFractions: libraryStore.resumeFractions(),
                    onOpen: { homeVideo = $0 }
                )
                .videoDestination($homeVideo, coordinator: playerCoordinator, library: libraryStore, localLibrary: localLibrary)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                AddView(model: localLibrary, onOpen: { addVideo = $0 }, onOpenPlaylist: { addPlaylist = $0 })
                    .navigationDestination(item: $addPlaylist) { playlist in
                        LocalPlaylistView(playlist: playlist, model: localLibrary) { addVideo = $0 }
                    }
                    .videoDestination($addVideo, coordinator: playerCoordinator, library: libraryStore, localLibrary: localLibrary)
            }
            .tabItem { Label("Add", systemImage: "plus.circle") }
            .tag(1)

            NavigationStack {
                LibraryView(store: libraryStore, playerCoordinator: playerCoordinator, localLibrary: localLibrary)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(3)
        }
        .task {
            await localLibrary.load()
            try? backgroundMedia.configureAudioSession()
            backgroundMedia.registerRemoteCommands()
            backgroundMedia.registerInterruptionObservation()
            backgroundMedia.registerRouteChangeObservation()
        }
    }
}

extension View {
    /// The video page is a pushed route, not a modal sheet (modal presentation
    /// of player content proved unreliable on iOS 26 runtimes).
    func videoDestination(_ item: Binding<VideoSummary?>, coordinator: PlayerCoordinator,
                          library: LibraryStore, localLibrary: LocalLibraryModel) -> some View {
        navigationDestination(item: item) { video in
            VideoPageView(video: video, coordinator: coordinator, library: library, localLibrary: localLibrary)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { item.wrappedValue = nil }
                    }
                }
        }
    }
}

/// A locally saved playlist, loaded from its public feed (most recent ~15 items).
struct LocalPlaylistView: View {
    let playlist: SavedPlaylist
    let model: LocalLibraryModel
    let onOpen: (VideoSummary) -> Void
    @State private var videos: [VideoSummary] = []
    @State private var failed = false

    var body: some View {
        List {
            if failed { Text("Couldn't load this playlist.").foregroundStyle(.secondary) }
            ForEach(videos) { video in
                Button { onOpen(video) } label: { VideoCard(video: video) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("playlist-video-row")
            }
            Text("Public feeds show a playlist's most recent items only.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle(playlist.title)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do { videos = try await model.playlistVideos(playlist.playlistID); failed = false } catch { failed = true }
    }
}

struct LibraryView: View {
    let store: LibraryStore
    let playerCoordinator: PlayerCoordinator
    let localLibrary: LocalLibraryModel

    @State private var selectedSummary: VideoSummary?
    @State private var selectedPlaylist: SavedPlaylist?

    var body: some View {
        List {
            continueWatchingSection
            historySection
            savedSection
            playlistsSection
            subscriptionsSection
        }
        .navigationTitle("Library")
        .navigationDestination(item: $selectedPlaylist) { playlist in
            LocalPlaylistView(playlist: playlist, model: localLibrary) { selectedSummary = $0 }
        }
        .videoDestination($selectedSummary, coordinator: playerCoordinator, library: store, localLibrary: localLibrary)
    }

    private func open(_ summary: VideoSummary) {
        selectedSummary = summary
    }

    /// Rebuilds the navigation payload from persisted fields. DDV2-08 keeps
    /// optional presentation metadata locally so reconstruction no longer
    /// loses duration/publish/thumbnail data; H3-03 (HB-029) adds channel id
    /// and description so Subscribe and More/Less survive Library-origin
    /// navigation. Legacy rows carry nil and degrade as before.
    private static func summary(from entry: WatchHistoryEntry) -> VideoSummary {
        VideoSummary(
            id: entry.videoID,
            title: entry.title,
            channelTitle: entry.channelTitle,
            durationSeconds: entry.durationSeconds,
            publishedAt: entry.publishedAt,
            thumbnailURL: entry.thumbnailURL.flatMap(URL.init(string:)),
            description: entry.videoDescription,
            channelID: entry.channelID
        )
    }

    private static func summary(from item: SavedItem) -> VideoSummary {
        VideoSummary(
            id: item.videoID,
            title: item.title,
            channelTitle: item.channelTitle,
            durationSeconds: item.durationSeconds,
            publishedAt: item.publishedAt,
            thumbnailURL: item.thumbnailURL.flatMap(URL.init(string:)),
            description: item.videoDescription,
            channelID: item.channelID
        )
    }

    // MARK: - Sections (DDV2-08)

    private var continueWatchingSection: some View {
        Section("Continue watching") {
            let inProgress = store.historySnapshot().filter { !$0.completed }
            if inProgress.isEmpty {
                Text("Nothing in progress.")
                    .foregroundStyle(.secondary)
            }
            ForEach(inProgress, id: \.videoID) { entry in
                Button {
                    open(Self.summary(from: entry))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).lineLimit(2)
                        Text(entry.channelTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let duration = entry.durationSeconds, duration > 0 {
                            ProgressView(
                                value: min(max(entry.lastPositionSeconds / Double(duration), 0), 1)
                            )
                            .tint(.red)
                        }
                    }
                }
                .accessibilityIdentifier("library-history-row")
                .accessibilityHint("Opens the video and resumes where you left off")
            }
            .onDelete { offsets in
                for index in offsets {
                    store.removeHistory(videoID: inProgress[index].videoID)
                }
            }
        }
    }

    private var historySection: some View {
        Section("Watch history") {
            let recent = Array(store.historySnapshot().prefix(20))
            if recent.isEmpty {
                Text("No watch history yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(recent, id: \.videoID) { entry in
                Button {
                    open(Self.summary(from: entry))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).lineLimit(1)
                                .font(.subheadline)
                            Text(entry.completed ? "Watched" : "Started")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    store.removeHistory(videoID: recent[index].videoID)
                }
            }
        }
    }

    private var savedSection: some View {
        Section("Saved") {
            let savedItems = store.savedSnapshot()
            if savedItems.isEmpty {
                Text("No saved videos yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(savedItems, id: \.videoID) { item in
                Button {
                    open(Self.summary(from: item))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).lineLimit(2)
                        Text(item.channelTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("library-saved-row")
                .accessibilityHint("Opens the saved video")
            }
            .onDelete { offsets in
                // Materialize the doomed rows BEFORE mutating: removing while
                // indexing would shift subsequent offsets onto the wrong rows.
                let doomed = offsets.compactMap { index in
                    savedItems.indices.contains(index) ? savedItems[index] : nil
                }
                for item in doomed {
                    store.removeSaved(videoID: item.videoID)
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section("Saved playlists") {
            let playlists = localLibrary.library.playlists
            if playlists.isEmpty {
                Text("Paste a playlist link in Add to save it here.").foregroundStyle(.secondary)
            }
            ForEach(playlists) { playlist in
                Button { selectedPlaylist = playlist } label: { Text(playlist.title).lineLimit(1) }
                    .accessibilityIdentifier("library-playlist-row")
            }
            .onDelete { offsets in
                let doomed = offsets.map { playlists[$0].playlistID }
                Task { for id in doomed { await localLibrary.removePlaylist(id) } }
            }
        }
    }

    private var subscriptionsSection: some View {
        Section("Subscriptions") {
            let subs = localLibrary.library.subscriptions
            if subs.isEmpty {
                Text("No subscriptions yet.").foregroundStyle(.secondary)
            }
            ForEach(subs) { sub in
                Text(sub.title.isEmpty ? sub.channelID.rawValue : sub.title)
                    .accessibilityIdentifier("library-subscription-row")
            }
            .onDelete { offsets in
                let doomed = offsets.map { subs[$0].channelID }
                Task { for id in doomed { await localLibrary.unsubscribe(id) } }
            }
        }
    }
}
