import SwiftUI
import FocusTubeCore

/// ADR-0008 Home: local subscriptions feed from public Atom feeds, with pull-to-refresh.
struct SubscriptionsFeedView: View {
    let model: LocalLibraryModel
    let resumeFractions: [String: Double]
    let onOpen: (VideoSummary) -> Void

    var body: some View {
        List {
            if model.library.subscriptions.isEmpty {
                ContentUnavailableView(
                    "No subscriptions yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Use the Add tab to paste a channel link (youtube.com/channel/UC…).")
                )
                .accessibilityIdentifier("feed-empty")
            } else {
                if !model.feedFailures.isEmpty {
                    Text("\(model.feedFailures.count) channel feed(s) couldn't be refreshed. Showing what's cached.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("feed-partial-failure")
                }
                ForEach(model.feed) { video in
                    Button { onOpen(video) } label: {
                        VideoCard(video: video, progressFraction: resumeFractions[video.id])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feed-video-row")
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh(force: true) }
        .overlay {
            if model.isRefreshing && model.feed.isEmpty { ProgressView() }
        }
        .navigationTitle("Home")
        .task { await model.refresh() }
    }
}
