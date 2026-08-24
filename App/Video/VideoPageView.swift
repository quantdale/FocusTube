import SwiftUI
import FocusTubeCore

/// Production video page: native player, available-only download quality picker,
/// comments with posting/replies, supported account actions with truthful
/// server-backed state, and offline-library registration. All data is fetched
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
    @State private var commentsError: YouTubeAPIError?
    @State private var isLoadingComments = false
    @State private var isDownloading = false
    @State private var isSaved = false

    // DDV2-04: account-action + composer state.
    @State private var ratingState: VideoRatingState?
    @State private var subscriptionLookup: SubscriptionLookup?
    @State private var didLoadSubscriptionState = false
    @State private var isTogglingLike = false
    @State private var isTogglingSubscribe = false
    @State private var accountActionError: YouTubeAPIError?
    @State private var composerText = ""
    @State private var replyTarget: Comment?
    @State private var isSubmittingComment = false

    private var commentsService: CommentsService { CommentsService(api: api) }
    private var accountActions: AccountActionsService { AccountActionsService(api: api) }

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

                metadataSection
                actionRow

                Divider()

                downloadSection

                Divider()

                commentsSection
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
        .alert(
            "Couldn't complete action",
            isPresented: Binding(
                get: { accountActionError != nil },
                set: { if !$0 { accountActionError = nil } }
            ),
            presenting: accountActionError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(accountErrorLabel(error))
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
                        completed: false,
                        publishedAt: video.publishedAt,
                        thumbnailURL: video.thumbnailURL?.absoluteString
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
            await loadAccountState()
        }
        .onDisappear {
            // Sheet dismissal must stop this page from recording watch-history
            // rows under its video ID — e.g. when local playback from Downloads
            // reuses the shared coordinator afterwards.
            coordinator.onProgress = nil
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title).font(.headline)
                .accessibilityIdentifier("video-title")
            HStack(spacing: 8) {
                Text(video.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("video-channel")
                if let published = video.publishedAt {
                    Text(Self.publishedLabel(published))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let duration = VideoCard.durationText(video.durationSeconds) {
                    Text(duration)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }
            descriptionBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var descriptionBlock: some View {
        if let description = video.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(isDescriptionExpanded ? nil : 2)
                .padding(.top, 2)
            Button(isDescriptionExpanded ? "Less" : "More") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDescriptionExpanded.toggle()
                }
            }
            .font(.caption.weight(.medium))
            .accessibilityIdentifier("description-toggle")
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                saveButton
                likeButton
                subscribeButton
                shareButton
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
    }

    private var saveButton: some View {
        Button {
            if isSaved {
                library.removeSaved(videoID: video.id)
                isSaved = false
            } else {
                library.save(
                    videoID: video.id,
                    title: video.title,
                    channelTitle: video.channelTitle,
                    durationSeconds: video.durationSeconds,
                    publishedAt: video.publishedAt,
                    thumbnailURL: video.thumbnailURL?.absoluteString
                )
                isSaved = true
            }
        } label: {
            Label(
                isSaved ? "Saved" : "Save",
                systemImage: isSaved ? "bookmark.fill" : "bookmark"
            )
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(isSaved ? "Remove from saved" : "Save video")
        .accessibilityIdentifier("save-toggle")
    }

    private var likeButton: some View {
        Button {
            Task { await toggleLike() }
        } label: {
            Label(
                ratingState == .like ? "Liked" : "Like",
                systemImage: ratingState == .like ? "hand.thumbsup.fill" : "hand.thumbsup"
            )
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .disabled(isTogglingLike)
        .accessibilityIdentifier("like-toggle")
        .accessibilityHint(ratingState == .like ? "Removes your rating" : "Rates this video positively")
    }

    @ViewBuilder
    private var subscribeButton: some View {
        // State comes from an authoritative subscriptions.list lookup, never
        // from prior taps. Requires the channel resource id from hydration.
        if let channelID = video.channelID {
            let subscribed = subscriptionLookup != nil
            Button {
                Task { await toggleSubscription(channelID: channelID) }
            } label: {
                Label(
                    subscribed ? "Subscribed" : "Subscribe",
                    systemImage: subscribed ? "bell.fill" : "bell"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!didLoadSubscriptionState || isTogglingSubscribe)
            .accessibilityIdentifier("subscribe-toggle")
            .accessibilityHint(subscribed ? "Unsubscribes from this channel" : "Subscribes to this channel")
        }
    }

    private var shareButton: some View {
        ShareLink(
            item: URL(string: "https://youtu.be/\(video.id)") ?? URL(fileURLWithPath: "/"),
            subject: Text(video.title)
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("share-button")
    }

    // MARK: - Download

    private var downloadSection: some View {
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
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comments")
                .font(.headline)

            if !commentsDisabled {
                composer
            }

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
                    commentBlock(comment)
                }
                if comments.isEmpty {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .padding(.bottom, 24)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target = replyTarget {
                HStack {
                    Text("Replying to \(target.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Cancel") {
                        replyTarget = nil
                    }
                    .font(.caption)
                }
            }
            HStack {
                TextField(replyTarget == nil ? "Add a comment…" : "Add a reply…", text: $composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("comment-composer-field")
                Button {
                    Task { await submitComment() }
                } label: {
                    if isSubmittingComment {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(isSubmittingComment || composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(replyTarget == nil ? "Post comment" : "Post reply")
                .accessibilityIdentifier("comment-submit")
            }
        }
    }

    private func commentBlock(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.author).font(.caption.bold())
            Text(comment.text)
            Button("Reply") {
                replyTarget = comment
                composerText = ""
            }
            .font(.caption)
            .accessibilityIdentifier("reply-button-\(comment.id)")
            ForEach(comment.replies) { reply in
                Text("↳ \(reply.author): \(reply.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Data loading

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

    /// Authoritative initial states for like/subscribe (never inferred from
    /// prior interactions). Silent best-effort: absence of state simply hides
    /// nothing — buttons stay enabled with neutral labels.
    private func loadAccountState() async {
        guard let token = await auth.accessToken() else { return }
        async let rating: Void = loadRating(token: token)
        async let subscription: Void = loadSubscriptionState(token: token)
        _ = await (rating, subscription)
    }

    private func loadRating(token: String) async {
        ratingState = try? await accountActions.ratingState(videoID: video.id, accessToken: token)
    }

    private func loadSubscriptionState(token: String) async {
        defer { didLoadSubscriptionState = true }
        guard let channelID = video.channelID else { return }
        subscriptionLookup = try? await accountActions.subscriptionState(channelID: channelID, accessToken: token)
    }

    // MARK: - Account mutations (optimistic with explicit rollback)

    private func toggleLike() async {
        guard let token = await auth.accessToken() else {
            accountActionError = .unauthorized
            return
        }
        let previous = ratingState ?? .none
        let next: VideoRatingState = previous == .like ? .none : .like
        ratingState = next
        isTogglingLike = true
        defer { isTogglingLike = false }
        do {
            if next == .like {
                try await accountActions.rate(videoID: video.id, rating: .like, accessToken: token)
            } else {
                try await accountActions.removeRating(videoID: video.id, accessToken: token)
            }
        } catch {
            ratingState = previous
            accountActionError = error as? YouTubeAPIError ?? .network
        }
    }

    private func toggleSubscription(channelID: String) async {
        guard let token = await auth.accessToken() else {
            accountActionError = .unauthorized
            return
        }
        let wasSubscribed = subscriptionLookup != nil
        isTogglingSubscribe = true
        defer { isTogglingSubscribe = false }
        do {
            if wasSubscribed {
                try await accountActions.unsubscribe(subscriptionID: subscriptionLookup!.subscriptionID, accessToken: token)
                subscriptionLookup = nil
            } else {
                try await accountActions.subscribe(channelID: channelID, accessToken: token)
                subscriptionLookup = try await accountActions.subscriptionState(channelID: channelID, accessToken: token)
            }
        } catch {
            subscriptionLookup = wasSubscribed ? subscriptionLookup : nil
            accountActionError = error as? YouTubeAPIError ?? .network
        }
    }

    // MARK: - Comment submission

    private func submitComment() async {
        guard let token = await auth.accessToken() else {
            accountActionError = .unauthorized
            return
        }
        // Duplicate-submit prevention: the flag gates re-entry synchronously
        // before any await, so double taps cannot fire two POSTs.
        guard !isSubmittingComment else { return }
        isSubmittingComment = true
        defer { isSubmittingComment = false }
        do {
            if let target = replyTarget {
                let stored = try await commentsService.reply(to: target.id, text: composerText, accessToken: token)
                if let index = comments.firstIndex(where: { $0.id == target.id }) {
                    let existing = comments[index]
                    // Comment is immutable-by-design; rebuild the thread row.
                    comments[index] = Comment(
                        id: existing.id,
                        author: existing.author,
                        text: existing.text,
                        likeCount: existing.likeCount,
                        publishedAt: existing.publishedAt,
                        replyCount: max(existing.replyCount, existing.replies.count + 1),
                        replies: existing.replies + [stored]
                    )
                }
                replyTarget = nil
            } else {
                let stored = try await commentsService.post(videoID: video.id, text: composerText, accessToken: token)
                comments.insert(stored, at: 0)
            }
            composerText = ""
        } catch {
            accountActionError = error as? YouTubeAPIError ?? .network
        }
    }

    // MARK: - Copy helpers

    private static func publishedLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func commentsErrorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .unauthorized: return "Sign in to post or see comments."
        case .quotaExceeded: return "Comments quota exceeded. Try again later."
        case .commentsDisabled: return "Comments are disabled for this video."
        case .notFound: return "Comments are unavailable for this video."
        case .network: return "Network error loading comments."
        case .decode: return "Couldn't load comments."
        case .invalidInput: return "That comment can't be sent. Check the text and try again."
        case .unknown: return "Couldn't load comments."
        }
    }

    private func accountErrorLabel(_ error: YouTubeAPIError) -> String {
        switch error {
        case .unauthorized: return "Sign in to use this action."
        case .quotaExceeded: return "YouTube API quota exceeded. Try again later."
        case .notFound: return "The item no longer exists."
        case .invalidInput: return "That input can't be submitted. Check it and try again."
        case .network: return "A network problem interrupted the action. Try again."
        case .decode: return "The response couldn't be read. Try again."
        case .unknown: return "The action failed. Try again."
        }
    }
}
