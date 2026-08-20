import SwiftUI
import FocusTubeCore

struct SearchView: View {
    @Bindable var store: SearchStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI

    @State private var queryText = ""
    @State private var showVideo = false
    @State private var selectedVideoID: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search YouTube", text: $queryText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                    Button("Search") {
                        Task { await store.submit(queryText) }
                    }
                    .disabled(queryText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if store.isLoading {
                ProgressView("Searching…")
            }

            if let error = store.error {
                Label(errorLabel(error), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.results) { video in
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

            if store.nextPageToken != nil {
                Button {
                    Task { await store.loadMore() }
                } label: {
                    Label("Load more", systemImage: "arrow.down.circle")
                }
            }
        }
        .navigationTitle("Search")
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

    private func errorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .quotaExceeded: return "Search quota exceeded. Try again later."
        case .unauthorized: return "Sign in to search."
        case .network: return "Network error."
        case .unknown: return "Search failed."
        default: return "Search unavailable."
        }
    }
}
