import SwiftUI
import UIKit
import FocusTubeCore

/// ADR-0008 "Add" tab (replaces Search): paste a video, playlist or channel
/// link, plus local search over already-known videos. No YouTube search.
struct AddView: View {
    let model: LocalLibraryModel
    let onOpen: (VideoSummary) -> Void
    let onOpenPlaylist: (SavedPlaylist) -> Void

    @State private var linkText = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var query = ""
    @FocusState private var focusedField: Field?

    private enum Field { case link, search }

    var body: some View {
        List {
            Section {
                TextField("Paste a YouTube link", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    .focused($focusedField, equals: .link)
                    .accessibilityIdentifier("add-link-field")
                HStack {
                    Button("Paste") {
                        if let s = UIPasteboard.general.string { linkText = s; submit() }
                    }
                    .accessibilityIdentifier("add-paste")
                    Spacer()
                    Button("Add") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("add-submit")
                }
                if isWorking { ProgressView() }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("add-message")
                }
            } header: {
                Text("Add by link")
            } footer: {
                Text("Videos, playlists and channel links (youtube.com/channel/UC…). Shorts aren't supported.")
            }

            Section("Search your library") {
                TextField("Search saved, history and feed", text: $query)
                    .focused($focusedField, equals: .search)
                    .accessibilityIdentifier("local-search-field")
                ForEach(model.localSearch(query)) { video in
                    Button { onOpen(video) } label: { VideoCard(video: video) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("local-search-row")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Add")
    }

    private func submit() {
        // Release the keyboard on submit so it never hides the tab bar after
        // a link is added (it previously stayed up and swallowed tab taps).
        focusedField = nil
        let text = linkText
        message = nil
        let link: YouTubeLink
        do { link = try YouTubeLink.parse(text) } catch let rejection as YouTubeLink.Rejection {
            message = rejection.userMessage
            return
        } catch {
            message = YouTubeLink.Rejection.unsupported.userMessage
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            switch link {
            case let .video(id, _, _):
                let (summary, isShort) = await model.summary(for: id)
                if isShort {
                    message = YouTubeLink.Rejection.shorts.userMessage
                } else {
                    linkText = ""
                    onOpen(summary)
                }
            case let .channel(id):
                do {
                    let title = try await model.subscribe(id)
                    linkText = ""
                    message = "Subscribed to \(title)."
                } catch let e as PublicSourceError where e == .notFound {
                    message = "Channel not found."
                } catch {
                    message = "Couldn't load that channel. Try again."
                }
            case let .playlist(id):
                do {
                    let feed = try await model.savePlaylist(id)
                    linkText = ""
                    message = "Saved playlist \(feed.title)."
                    if let saved = model.library.playlists.first(where: { $0.playlistID == id }) { onOpenPlaylist(saved) }
                } catch let e as PublicSourceError where e == .notFound {
                    message = "Playlist not found (private playlists can't be added)."
                } catch {
                    message = "Couldn't load that playlist. Try again."
                }
            }
        }
    }
}
