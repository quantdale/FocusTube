import SwiftUI
import FocusTubeCore

/// ADR-0008 video page: official IFrame player (ADR-0007), metadata from the
/// feed/oEmbed, local Watch Later and local subscribe, share and Open in
/// YouTube. No comments, ratings or account actions (no Google account).
struct VideoPageView: View {
    let video: VideoSummary
    @Bindable var coordinator: PlayerCoordinator
    let library: LibraryStore
    let localLibrary: LocalLibraryModel

    @State private var isSaved = false
    @State private var isDescriptionExpanded = false
    @State private var channelTitle: String?
    @State private var blockedAsShort = false
    @Environment(\.openURL) private var openURL

    private var channelID: YouTubeChannelID? { video.channelID.flatMap(YouTubeChannelID.init) }
    private var watchURL: URL? {
        YouTubeVideoID(video.id).flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.rawValue)") }
    }
    private var knownDuration: Int? {
        let d = coordinator.engineState.duration
        return d > 0 ? Int(d.rounded()) : video.durationSeconds
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if blockedAsShort {
                    ContentUnavailableView(
                        "Short video blocked",
                        systemImage: "hand.raised",
                        description: Text("FocusTube hides videos of 3 minutes or less.")
                    )
                    .frame(height: 240)
                    .accessibilityIdentifier("short-blocked")
                } else {
                    PlayerView(coordinator: coordinator)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                }
                metadataHeader
                actionRow
                Divider()
                descriptionSection
            }
        }
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            coordinator.onProgress = { seconds in
                let duration = coordinator.engineState.duration > 0 ? Int(coordinator.engineState.duration.rounded()) : video.durationSeconds
                Task {
                    await library.recordProgress(
                        videoID: video.id,
                        title: video.title,
                        channelTitle: displayChannel,
                        position: seconds,
                        duration: duration,
                        completed: false,
                        publishedAt: video.publishedAt,
                        thumbnailURL: video.thumbnailURL?.absoluteString,
                        channelID: video.channelID,
                        videoDescription: video.description
                    )
                }
            }
            coordinator.nowPlayingTitle = video.title
            coordinator.nowPlayingArtist = video.channelTitle
            isSaved = library.isSaved(videoID: video.id)
            await coordinator.loadAndPlay(videoID: video.id, resumeAt: library.resumePosition(for: video.id))
            if video.channelTitle.isEmpty, let id = YouTubeVideoID(video.id) {
                channelTitle = await localLibrary.metadata(for: id)?.authorName
            }
        }
        .onChange(of: coordinator.engineState.duration) { _, duration in
            guard duration > 0 else { return }
            Task { await localLibrary.learnDuration(videoID: video.id, seconds: duration) }
            // ADR-0008 Shorts rule d: a duration ≤180 s learned from the player blocks playback.
            if ShortFormPolicy().isBlocked(durationSeconds: Int(duration.rounded())) {
                coordinator.stop()
                blockedAsShort = true
            }
        }
        .onDisappear { coordinator.onProgress = nil }
    }

    private var displayChannel: String { channelTitle ?? video.channelTitle }

    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title).font(.headline)
                .accessibilityIdentifier("video-title")
            HStack(spacing: 8) {
                Text(displayChannel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("video-channel")
                if let published = VideoCard.relativePublished(video.publishedAt) {
                    Text(published).font(.caption).foregroundStyle(.secondary)
                }
                if let duration = VideoCard.durationText(knownDuration) {
                    Text(duration)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    if isSaved {
                        library.removeSaved(videoID: video.id)
                    } else {
                        library.save(videoID: video.id, title: video.title, channelTitle: displayChannel,
                                     durationSeconds: knownDuration, publishedAt: video.publishedAt,
                                     thumbnailURL: video.thumbnailURL?.absoluteString, channelID: video.channelID,
                                     videoDescription: video.description)
                    }
                    isSaved = library.isSaved(videoID: video.id)
                } label: {
                    Label(isSaved ? "Saved" : "Watch later", systemImage: isSaved ? "clock.fill" : "clock")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("save-toggle")
                .accessibilityLabel(isSaved ? "Remove from saved" : "Save video")

                if let channelID {
                    let subscribed = localLibrary.isSubscribed(channelID)
                    Button {
                        Task {
                            if subscribed { await localLibrary.unsubscribe(channelID) }
                            else { await localLibrary.subscribe(channelID, title: displayChannel) }
                        }
                    } label: {
                        Label(subscribed ? "Subscribed" : "Subscribe", systemImage: subscribed ? "bell.fill" : "bell")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("subscribe-toggle")
                }

                if let watchURL {
                    ShareLink(item: watchURL, subject: Text(video.title)) {
                        Label("Share", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share-button")

                    Button {
                        openURL(watchURL)
                    } label: {
                        Label("Open in YouTube", systemImage: "arrow.up.right.square").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("open-in-youtube")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if let description = video.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(isDescriptionExpanded ? nil : 3)
                Button(isDescriptionExpanded ? "Less" : "More") { isDescriptionExpanded.toggle() }
                    .font(.caption.weight(.medium))
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("description-toggle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }
}
