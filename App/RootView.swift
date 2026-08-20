import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                PlaceholderView(title: "Home", message: "Chronological long-form subscription feed")
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
