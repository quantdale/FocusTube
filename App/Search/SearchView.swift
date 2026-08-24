import SwiftUI
import FocusTubeCore

struct SearchView: View {
    @Bindable var store: SearchStore
    @Bindable var recentSearches: RecentSearchStore
    let playerCoordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService
    let library: LibraryStore

    @State private var queryText = ""
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
                        .accessibilityIdentifier("search-field")
                    Button("Search") {
                        submit()
                    }
                    .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("search-submit-button")
                }
            }

            recentsSection

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
                } label: {
                    VideoCard(
                        video: video,
                        progressFraction: VideoCard.resumeFraction(videoID: video.id, history: library.history)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search-result-row")
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
        .navigationTitle("Search")
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

    /// Single explicit-submit path shared by the keyboard (Return/Search key)
    /// and the button. Whitespace-only queries are rejected without an API call;
    /// the trimmed text is what gets submitted and recorded as a recent query.
    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.record(trimmed)
        Task { await store.submit(trimmed) }
    }

    // MARK: - Recents (DDV2-07)

    /// Local suggestions while typing + persisted recents when idle. Purely
    /// local state — typing alone can never trigger a remote call.
    @ViewBuilder
    private var recentsSection: some View {
        let typed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let differsFromSubmitted = typed != store.query
        if !typed.isEmpty, differsFromSubmitted {
            let suggestions = recentSearches.suggestions(for: typed)
            if !suggestions.isEmpty {
                Section("Suggestions") {
                    ForEach(suggestions, id: \.query) { suggestion in
                        Button {
                            queryText = suggestion.query
                            submit()
                        } label: {
                            Label(suggestion.query, systemImage: "clock.arrow.circlepath")
                                .lineLimit(1)
                        }
                        .accessibilityIdentifier("search-suggestion-row")
                    }
                }
            }
        } else if !recentSearches.entries.isEmpty {
            Section {
                ForEach(recentSearches.entries, id: \.query) { entry in
                    HStack {
                        Button {
                            queryText = entry.query
                            submit()
                        } label: {
                            Label(entry.query, systemImage: "clock.arrow.circlepath")
                                .lineLimit(1)
                        }
                        .accessibilityIdentifier("recent-search-row")
                        Spacer()
                        Button(role: .destructive) {
                            recentSearches.remove(entry.query)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .accessibilityLabel("Remove \(entry.query) from recents")
                    }
                }
                Button(role: .destructive) {
                    recentSearches.clear()
                } label: {
                    Label("Clear search history", systemImage: "trash")
                }
                .accessibilityIdentifier("clear-search-history")
            } header: {
                Text("Recent searches")
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
