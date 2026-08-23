import SwiftUI
import FocusTubeCore

/// Production video page: native player, available-only download quality picker,
/// comments (with disabled and error handling), account actions, and a download
/// action that registers the finalized file in the offline library. All data is
/// fetched live; failures degrade gracefully without leaking short-form content.
struct VideoPageView: View {
    let video: VideoSummary
    @Bindable var coordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI
    let downloadService: DownloadService
    let library: LibraryStore

    @State private var qualities: [DownloadQuality] = []
    @State private var selectedQuality: DownloadQuality?
    @State private var comments: [Comment] = []
    @State private var commentsDisabled = false
    @State private var commentsError: YouTubeAPIError?
    @State private var isLoadingComments = false
    @State private var isDownloading = false
    @State private var isSaved = false

    private var commentsService: CommentsService { CommentsService(api: api) }

    /// The quality the button acts on (picker selection or the 720p default).
    private var effectiveQuality: DownloadQuality { selectedQuality ?? .p720 }

    /// In-flight while this view awaits the service, or while the manager's
    /// observable live-task projection still holds a transfer for this
    /// video+quality (covers view recreation mid-download).
    @MainActor
    private var downloadInFlight: Bool {
        isDownloading || downloadService.isInFlight(videoID: video.id, quality: effectiveQuality)
    }

    var body: some View {
        // A bounded detail page uses a plain scroll view: List laziness only
        // materializes near-viewport rows on current iOS runtimes, which made
        // below-the-fold controls intermittently absent from both the
        // accessibility hierarchy and XCUITest queries.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlayerView(coordinator: coordinator)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title).font(.headline)
                        .accessibilityIdentifier("video-title")
                    Text(video.channelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("video-channel")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)

                Button {
                    if isSaved {
                        library.removeSaved(videoID: video.id)
                        isSaved = false
                    } else {
                        library.save(
                            videoID: video.id,
                            title: video.title,
                            channelTitle: video.channelTitle
                        )
                        isSaved = true
                    }
                } label: {
                    Label(
                        isSaved ? "Saved" : "Save",
                        systemImage: isSaved ? "bookmark.fill" : "bookmark"
                    )
                }
                .accessibilityLabel(isSaved ? "Remove from saved" : "Save video")
                .accessibilityIdentifier("save-toggle")
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Download quality")
                        .font(.headline)
                    DownloadQualityPickerView(available: qualities, selection: $selectedQuality)
                    Button {
                        Task {
                            isDownloading = true
                            await downloadService.download(
                                videoID: video.id,
                                title: video.title,
                                channelTitle: video.channelTitle,
                                quality: effectiveQuality,
                                durationSeconds: Double(video.durationSeconds ?? 0)
                            )
                            isDownloading = false
                        }
                    } label: {
                        if downloadInFlight {
                            Label("Downloading…", systemImage: "arrow.down.circle")
                        } else {
                            Label("Download", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(downloadInFlight || qualities.isEmpty)
                    .accessibilityIdentifier("download-button")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Comments")
                        .font(.headline)
                    if commentsDisabled {
                        Text("Comments are disabled for this video.")
                            .foregroundStyle(.secondary)
                    } else if isLoadingComments {
                        ProgressView()
                    } else if let commentsError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(commentsErrorLabel(commentsError), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                            Button("Retry") {
                                Task { await loadComments() }
                            }
                        }
                    } else {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.author).font(.caption.bold())
                                Text(comment.text)
                                ForEach(comment.replies) { reply in
                                    Text("↳ \(reply.text)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Video")
        .alert(
            "Download failed",
            isPresented: Binding(
                get: { downloadService.lastFailure != nil },
                set: { if !$0 { downloadService.acknowledgeFailure() } }
            ),
            presenting: downloadService.lastFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.userMessage)
        }
        .task {
            // Register callbacks and Now Playing metadata before playback
            // starts so early progress ticks and state transitions are not
            // missed by late registration.
            coordinator.onProgress = { seconds in
                Task {
                    await library.recordProgress(
                        videoID: video.id,
                        title: video.title,
                        channelTitle: video.channelTitle,
                        position: seconds,
                        duration: video.durationSeconds,
                        completed: false
                    )
                }
            }
            coordinator.nowPlayingTitle = video.title
            coordinator.nowPlayingArtist = video.channelTitle
            isSaved = library.isSaved(videoID: video.id)
            await coordinator.loadAndPlay(
                videoID: video.id,
                resumeAt: library.resumePosition(for: video.id)
            )
            await loadQualities()
            await loadComments()
        }
        .onDisappear {
            // Sheet dismissal must stop this page from recording watch-history
            // rows under its video ID — e.g. when local playback from Downloads
            // reuses the shared coordinator afterwards.
            coordinator.onProgress = nil
        }
    }

    private func loadQualities() async {
        // Reuse the coordinator's extraction when it belongs to this video;
        // only fall back to a second extraction if playback never resolved.
        let resolved: ResolvedMedia?
        if let cached = coordinator.lastResolvedMedia, cached.videoID == video.id {
            resolved = cached
        } else {
            resolved = try? await YouTubeKitMediaExtractor().resolve(videoID: video.id)
        }
        guard let resolved else {
            qualities = []
            return
        }
        let picker = DownloadQualityPicker()
        qualities = picker.availableQualities(from: resolved)
        selectedQuality = qualities.first
    }

    private func loadComments() async {
        guard let token = await auth.accessToken() else { return }
        isLoadingComments = true
        commentsError = nil
        defer { isLoadingComments = false }
        do {
            let page = try await commentsService.comments(videoID: video.id, accessToken: token)
            comments = page.comments
            commentsDisabled = page.commentsDisabled
        } catch let error as YouTubeAPIError where error == .commentsDisabled {
            commentsDisabled = true
        } catch {
            // Non-disabled failures stay distinguishable from "no comments";
            // non-API errors (e.g. low-level transport) surface as .network.
            commentsError = error as? YouTubeAPIError ?? .network
            commentsDisabled = false
        }
    }

    private func commentsErrorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .unauthorized: return "Sign in to see comments."
        case .quotaExceeded: return "Comments quota exceeded. Try again later."
        case .commentsDisabled: return "Comments are disabled for this video."
        case .notFound: return "Comments are unavailable for this video."
        case .network: return "Network error loading comments."
        case .decode: return "Couldn't load comments."
        case .unknown: return "Couldn't load comments."
        }
    }
}
