import SwiftUI
import os
import FocusTubeCore

struct RootView: View {
    private static let logger = Logger(subsystem: "com.quantdale.FocusTube", category: "app-shell")

    let dependencies: AppDependencies

    // Long-lived dependencies are owned by AppDependencies (created once per
    // process); these accessors keep the body below readable.
    private var homeStore: HomeFeedStore { dependencies.homeStore }
    private var searchStore: SearchStore { dependencies.searchStore }
    private var auth: AuthSession { dependencies.auth }
    private var api: YouTubeAPI { dependencies.api }
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
                    recentSearches: dependencies.recentSearches,
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
            // Durable queue reconstruction (DDV2-01): after launch
            // reconciliation, persisted `.queued` downloads re-enter the FIFO
            // promotion queue so they survive process death.
            await downloadService.restorePersistedQueue()
        }
    }
}

struct LibraryView: View {
    let store: LibraryStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService

    @State private var selectedSummary: VideoSummary?
    @State private var playlistsState: PlaylistsLoadState = .idle
    @State private var selectedPlaylist: PlaylistSummary?

    private var accountActions: AccountActionsService { AccountActionsService(api: api) }

    enum PlaylistsLoadState {
        case idle, loading, loaded([PlaylistSummary]), failed(String)
    }

    var body: some View {
        List {
            continueWatchingSection
            historySection
            savedSection
            playlistsSection
        }
        .navigationTitle("Library")
        .navigationDestination(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist, api: api, auth: auth) { summary in
                selectedSummary = summary
            }
        }
        // The video page is a pushed route, not a modal sheet: modal
        // presentation of AVKit-hosting content proved unreliable on current
        // iOS 26 runtimes (content never reached the accessibility hierarchy),
        // while a stack push keeps the deliberate long-form flow and gives the
        // page real back-swipe/navigation semantics.
        .navigationDestination(item: $selectedSummary) { summary in
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
                    Button("Close") { selectedSummary = nil }
                }
            }
        }
    }

    private func open(_ summary: VideoSummary) {
        selectedSummary = summary
    }

    /// Rebuilds the navigation payload from persisted fields. DDV2-08 keeps
    /// optional presentation metadata locally so reconstruction no longer
    /// loses duration/publish/thumbnail data.
    private static func summary(from entry: WatchHistoryEntry) -> VideoSummary {
        VideoSummary(
            id: entry.videoID,
            title: entry.title,
            channelTitle: entry.channelTitle,
            durationSeconds: entry.durationSeconds,
            publishedAt: entry.publishedAt,
            thumbnailURL: entry.thumbnailURL.flatMap(URL.init(string:)),
            description: nil
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
            description: nil
        )
    }

    // MARK: - Sections (DDV2-08)

    private var continueWatchingSection: some View {
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
            let recent = Array(store.history.prefix(20))
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
                .accessibilityIdentifier("library-saved-row")
                .accessibilityHint("Opens the saved video")
            }
            .onDelete { offsets in
                // Materialize the doomed rows BEFORE mutating: `store.saved`
                // re-fetches on every access, so removing while indexing would
                // shift subsequent offsets onto the wrong rows.
                let doomed = offsets.compactMap { index in
                    store.saved.indices.contains(index) ? store.saved[index] : nil
                }
                for item in doomed {
                    store.removeSaved(videoID: item.videoID)
                }
            }
        }
    }

    /// Bounded supported-playlists surface: user's own playlists, fetched only
    /// when the user opens this section (explicit action, quota-appropriate).
    private var playlistsSection: some View {
        Section("Your YouTube playlists") {
            switch playlistsState {
            case .idle:
                Button {
                    Task { await loadPlaylists() }
                } label: {
                    Label("Show my playlists", systemImage: "list.triangle")
                }
                .accessibilityIdentifier("library-show-playlists")
            case .loading:
                ProgressView()
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await loadPlaylists() }
                    }
                }
            case .loaded(let playlists):
                if playlists.isEmpty {
                    Text("No playlists found.").foregroundStyle(.secondary)
                }
                ForEach(playlists, id: \.id) { playlist in
                    Button {
                        selectedPlaylist = playlist
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title).lineLimit(1)
                                Text("\(playlist.itemCount) video\(playlist.itemCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("playlist-row-\(playlist.id)")
                }
            }
        }
    }

    private func loadPlaylists() async {
        guard let token = await auth.accessToken() else {
            playlistsState = .failed("Sign in to see your playlists.")
            return
        }
        playlistsState = .loading
        do {
            playlistsState = .loaded(try await accountActions.playlists(accessToken: token))
        } catch let error as YouTubeAPIError {
            playlistsState = .failed(Self.playlistsErrorLabel(error))
        } catch {
            playlistsState = .failed("Couldn't load playlists.")
        }
    }

    private static func playlistsErrorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .unauthorized: return "Sign in to see your playlists."
        case .quotaExceeded: return "YouTube quota exceeded. Try again later."
        default: return "Couldn't load playlists."
        }
    }
}

/// Items of one user playlist with per-item removal (bounded first page).
struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    let api: YouTubeAPI
    let auth: AuthSession
    let onOpenVideo: (VideoSummary) -> Void

    @State private var items: [PlaylistItemSummary] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var removalError: String?

    var body: some View {
        List {
            if let message = removalError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Try again") {
                        removalError = nil
                        Task { await load() }
                    }
                }
            }
            if isLoading {
                ProgressView()
            } else if let errorText {
                Text(errorText).foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("This playlist is empty.").foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.playlistItemID) { item in
                    Button {
                        onOpenVideo(VideoSummary(
                            id: item.videoID,
                            title: item.title,
                            channelTitle: item.channelTitle,
                            durationSeconds: nil,
                            publishedAt: nil,
                            thumbnailURL: nil,
                            description: nil,
                            channelID: nil
                        ))
                    } label: {
                        Text(item.title).lineLimit(2)
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { items[$0] }
                    Task {
                        await remove(doomed)
                    }
                }
            }
        }
        .navigationTitle(playlist.title)
        .task { await load() }
    }

    private func load() async {
        guard let token = await auth.accessToken() else {
            errorText = "Sign in to see this playlist."
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await api.fetchPlaylistItems(playlistID: playlist.id, accessToken: token)
        } catch {
            errorText = "Couldn't load this playlist."
        }
    }

    private func remove(_ doomed: [PlaylistItemSummary]) async {
        guard let token = await auth.accessToken() else {
            removalError = "Sign in to manage this playlist."
            return
        }
        var failedIDs: Set<String> = []
        for item in doomed {
            do {
                try await api.removeFromPlaylist(playlistItemID: item.playlistItemID, accessToken: token)
            } catch {
                failedIDs.insert(item.playlistItemID)
            }
        }
        // Only rows the server actually removed leave the list; a failed
        // delete must not fabricate local state that resurrects on re-fetch.
        let removedIDs = Set(doomed.map(\.playlistItemID)).subtracting(failedIDs)
        items.removeAll { removedIDs.contains($0.playlistItemID) }
        if !failedIDs.isEmpty {
            removalError = "Some videos couldn't be removed. Try again."
        }
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

    @State private var selectedVideo: VideoSummary?
    @State private var showSettings = false

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
            if let error = store.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(Self.errorLabel(error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await store.load() }
                    }
                }
                .accessibilityIdentifier("home-error")
            } else if !store.isLoading,
                      store.isAuthenticated,
                      store.videos.isEmpty {
                Text("No long-form videos from your subscriptions yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("home-empty")
            }
            ForEach(store.videos) { video in
                Button {
                    selectedVideo = video
                } label: {
                    VideoCard(
                        video: video,
                        progressFraction: VideoCard.resumeFraction(videoID: video.id, history: library.history)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed-video-row")
            }
            if store.nextPageToken != nil {
                Button {
                    Task { await store.loadMore() }
                } label: {
                    Label("Load more", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("load-more-button")
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Account and settings")
                .accessibilityIdentifier("settings-button")
            }
        }
        .sheet(isPresented: $showSettings) {
            AccountSettingsView(store: store, auth: auth, library: library)
        }
        .refreshable {
            // Explicit user action: a deliberate page-one reload is
            // quota-appropriate, unlike automatic refetches on tab switches.
            await store.load()
        }
        .task {
            // Auto-load ONLY a still-empty feed: tab switches must not re-fetch
            // the whole subscription aggregate (quota churn) or clobber scroll
            // position. Explicit recovery paths are the Try-again button and
            // the sign-in CTA.
            guard store.videos.isEmpty else { return }
            await store.restore()
            await store.load()
        }
        // Pushed video page (see LibraryView note): modal presentation of
        // AVKit-hosting content is unreliable on current iOS 26 runtimes.
        .navigationDestination(item: $selectedVideo) { video in
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
                    Button("Close") { selectedVideo = nil }
                }
            }
        }
    }

    private static func errorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .quotaExceeded: return "Subscription quota exceeded. Try again later."
        case .unauthorized: return "Sign in to see your subscriptions."
        case .network: return "Network error loading your subscriptions."
        case .unknown: return "Couldn't load your subscriptions."
        default: return "Subscriptions unavailable."
        }
    }
}
