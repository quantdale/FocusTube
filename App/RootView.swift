import SwiftUI

struct RootView: View {
    @State private var playerCoordinator = PlayerCoordinator()

    var body: some View {
        TabView {
            NavigationStack {
                HomePlaceholder(playerCoordinator: playerCoordinator)
            }
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                PlaceholderView(title: "Search", message: "Explicit-submit YouTube search")
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

/// M1 viability demo: opens the native player for a representative long-form
/// sample. Replaced by the real subscription Home feed in a later milestone.
private struct HomePlaceholder: View {
    let playerCoordinator: PlayerCoordinator

    @State private var showPlayer = false
    private let sampleVideoID = "aqz-KE-bpKQ"

    var body: some View {
        List {
            PlaceholderView(title: "Home", message: "Chronological long-form subscription feed")
            Button {
                showPlayer = true
            } label: {
                Label("Open native player (M1 demo)", systemImage: "play.circle")
            }
        }
        .navigationTitle("Home")
        .sheet(isPresented: $showPlayer) {
            NavigationStack {
                PlayerView(coordinator: playerCoordinator)
                    .navigationTitle("Playback")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { showPlayer = false }
                        }
                    }
                    .task { await playerCoordinator.loadAndPlay(videoID: sampleVideoID) }
            }
        }
    }
}
