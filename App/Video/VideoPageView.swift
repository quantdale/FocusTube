import SwiftUI
import FocusTubeCore

/// Production video page: native player, available-only download quality picker,
/// comments (with disabled handling), account actions, and a download action
/// that registers the finalized file in the offline library. All data is fetched
/// live; failures degrade gracefully without leaking short-form content.
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
    @State private var isLoadingComments = false
    @State private var isDownloading = false

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
        List {
            PlayerView(coordinator: coordinator)
                .frame(height: 240)
                .listRowInsets(EdgeInsets())

            Section("Download quality") {
                DownloadQualityPickerView(available: qualities, selection: $selectedQuality)
                Button {
                    Task {
                        isDownloading = true
                        await downloadService.download(
                            videoID: video.id,
                            title: video.title,
                            channelTitle: video.channelTitle,
                            quality: effectiveQuality
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
            }

            Section("Comments") {
                if commentsDisabled {
                    Text("Comments are disabled for this video.")
                        .foregroundStyle(.secondary)
                } else if isLoadingComments {
                    ProgressView()
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
            await coordinator.loadAndPlay(videoID: video.id)
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
            await loadQualities()
            await loadComments()
        }
    }

    private func loadQualities() async {
        do {
            let resolved = try await YouTubeKitMediaExtractor().resolve(videoID: video.id)
            let picker = DownloadQualityPicker()
            qualities = picker.availableQualities(from: resolved)
            selectedQuality = qualities.first
        } catch {
            qualities = []
        }
    }

    private func loadComments() async {
        guard let token = await auth.accessToken() else { return }
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            let page = try await commentsService.comments(videoID: video.id, accessToken: token)
            comments = page.comments
            commentsDisabled = page.commentsDisabled
        } catch let error as YouTubeAPIError where error == .commentsDisabled {
            commentsDisabled = true
        } catch {
            commentsDisabled = false
        }
    }
}
