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
    /// SwiftUI-owned field focus. Submit deliberately RETAINS focus: a
    /// programmatic blur desynced SwiftUI's internal focus state on iOS 26 and
    /// left the field un-refocusable by tap (evidence: runs 32828052990 /
    /// dfb939b). Keyboard obstruction is instead resolved on the scroll side:
    /// any drag immediately drops the keyboard so results render full-height.
    @FocusState private var queryFieldFocused: Bool

    var body: some View {
        // A deliberate NON-lazy scroll view (same contract as DownloadsView and
        // the video page): personal-scale result pages make laziness worthless,
        // while a lazy List refused to realize the below-fold Load-more row at
        // all while the keyboard compressed the viewport (run 8ad4c69 — 18
        // attempts, empty frame breadcrumbs). Existence equals render here.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchFieldRow

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

                // HB-027: one projection fetch per body evaluation, not one
                // full-history scan per card row.
                let resumeFractions = library.resumeFractions()
                ForEach(store.results) { video in
                    Button {
                        selectedVideo = video
                    } label: {
                        VideoCard(
                            video: video,
                            progressFraction: resumeFractions[video.id]
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
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Search")
        // Any scroll over the results immediately drops the keyboard so
        // below-fold controls are reachable at full height; submit keeps field
        // focus.
        .scrollDismissesKeyboard(.immediately)
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

    private var searchFieldRow: some View {
        HStack {
            TextField("Search YouTube", text: $queryText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit(submit)
                .focused($queryFieldFocused)
                .accessibilityLabel("Search query")
                .accessibilityIdentifier("search-field")
            Button("Search") {
                submit()
            }
            .disabled(
                queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (store.isLoading && queryText.trimmingCharacters(in: .whitespacesAndNewlines) == store.query)
            )
            .accessibilityIdentifier("search-submit-button")
        }
    }

    /// Single explicit-submit path shared by the keyboard (Return/Search key)
    /// and the button. Whitespace-only queries are rejected without an API call;
    /// the trimmed text is what gets submitted and recorded as a recent query.
    /// Field focus is intentionally retained across submits (see the
    /// @FocusState note); scrolling the results dismisses the keyboard.
    /// HB-029: an identical query already in flight is dropped BEFORE any
    /// work — repeated identical submits must not burn search quota. A
    /// DIFFERENT query always supersedes (generation guard in the store
    /// keeps state safety).
    private func submit() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if store.isLoading, trimmed == store.query { return }
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
                sectionHeader("Suggestions")
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
        } else if !recentSearches.entries.isEmpty {
            sectionHeader("Recent searches")
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
                            .frame(minWidth: 44, minHeight: 44)
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
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func errorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .quotaExceeded: return "Search quota exceeded. Try again later."
        case .unauthorized: return "Sign in to search."
        case .forbidden: return "Search isn't permitted for this account."
        case .network: return "Network error."
        case .unknown: return "Search failed."
        default: return "Search unavailable."
        }
    }
}
