import SwiftUI
import FocusTubeCore

struct SearchView: View {
    @Bindable var store: SearchStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService
    let library: LibraryStore

    @State private var queryText = ""
    @State private var showVideo = false
    @State private var selectedVideo: VideoSummary?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Search YouTube", text: $queryText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit(submit)
                        .accessibilityLabel("Search query")
                    Button("Search") {
                        submit()
                    }
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if store.isLoading {
                ProgressView("Searching…")
            }

            if let error = store.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label(errorLabel(error), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        // Retry resubmits the last EXECUTED query, not whatever
                        // currently sits in the field.
                        queryText = store.query
                        submit()
                    }
                }
            } else if !store.isLoading,
                      !store.query.isEmpty,
                      store.results.isEmpty {
                Text("No results for \"\(store.query)\".")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.results) { video in
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
        .navigationTitle("Search")
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

    /// Single explicit-submit path shared by the keyboard (Return/Search key)
    /// and the button. Whitespace-only queries are rejected without an API call;
    /// the trimmed text is what gets submitted.
    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await store.submit(trimmed) }
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
