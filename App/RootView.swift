import SwiftUI

struct RootView: View {
    @State private var playerCoordinator = PlayerCoordinator()
    @State private var homeStore = HomeFeedStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var searchStore = SearchStore(auth: GoogleSignInAuthSession(), api: YouTubeDataClient())
    @State private var auth: AuthSession = GoogleSignInAuthSession()
    @State private var api: YouTubeAPI = YouTubeDataClient()

    var body: some View {
        TabView {
            NavigationStack {
                HomeFeedView(store: homeStore, playerCoordinator: playerCoordinator, auth: auth, api: api)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                SearchView(store: searchStore, playerCoordinator: playerCoordinator, auth: auth, api: api)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                PlaceholderView(title: "Downloads", message: "1080p / 720p / 480p / 360p offline library")
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            NavigationStack {
                PlaceholderView(title: "Library", message: "Local history, progress, saves, and playlists")
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
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

/// Chronological long-form subscription Home feed with the short-form firewall
/// applied before render. Load-more is an explicit user action.
private struct HomeFeedView: View {
    @Bindable var store: HomeFeedStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI

    @State private var showVideo = false
    @State private var selectedVideoID: String?

    var body: some View {
        List {
            if store.isLoading {
                ProgressView("Loading feed…")
            }
            ForEach(store.videos) { video in
                Button {
                    selectedVideoID = video.id
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
                selectedVideoID = "aqz-KE-bpKQ"
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
            if let id = selectedVideoID {
                NavigationStack {
                    VideoPageView(videoID: id, coordinator: playerCoordinator, auth: auth, api: api)
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
