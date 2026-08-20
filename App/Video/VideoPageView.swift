import SwiftUI
import FocusTubeCore

/// Production video page: native player, available-only download quality picker,
/// comments (with disabled handling), and supported account actions. All data is
/// fetched live; failures degrade gracefully without leaking short-form content.
struct VideoPageView: View {
    let videoID: String
    @Bindable var coordinator: PlayerCoordinator
    let auth: AuthSession
    let api: YouTubeAPI

    @State private var qualities: [DownloadQuality] = []
    @State private var selectedQuality: DownloadQuality?
    @State private var comments: [Comment] = []
    @State private var commentsDisabled = false
    @State private var isLoadingComments = false

    private var commentsService: CommentsService { CommentsService(api: api) }

    var body: some View {
        List {
            PlayerView(coordinator: coordinator)
                .frame(height: 240)
                .listRowInsets(EdgeInsets())

            Section("Download quality") {
                DownloadQualityPickerView(available: qualities, selection: $selectedQuality)
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
        .task {
            await coordinator.loadAndPlay(videoID: videoID)
            await loadQualities()
            await loadComments()
        }
    }

    private func loadQualities() async {
        do {
            let resolved = try await YouTubeKitMediaExtractor().resolve(videoID: videoID)
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
            let page = try await commentsService.comments(videoID: videoID, accessToken: token)
            comments = page.comments
            commentsDisabled = page.commentsDisabled
        } catch let error as YouTubeAPIError where error == .commentsDisabled {
            commentsDisabled = true
        } catch {
            commentsDisabled = false
        }
    }
}
