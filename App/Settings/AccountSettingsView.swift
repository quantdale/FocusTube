import SwiftUI
import FocusTubeCore

/// Account/settings access surface (product spec docs/00: reached from a
/// profile control, never a fifth tab). Contains authentication state,
/// sign-in/out, product principles, download policy, storage summary, and
/// privacy information. No analytics, no trackers, no cloud backends.
struct AccountSettingsView: View {
    @Bindable var store: HomeFeedStore
    let auth: AuthSession
    let library: LibraryStore

    @Environment(\.dismiss) private var dismiss
    /// HB-029 sign-in re-entry guard.
    @State private var isSigningIn = false
    /// HB-029 truthful degraded-state notice (fake/test sessions).
    @State private var signInNotice: String?

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                principlesSection
                downloadPolicySection
                storageSection
                privacySection
                aboutSection
            }
            .navigationTitle("Account & Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.restore() }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            if store.isAuthenticated {
                Label("Signed in with Google", systemImage: "person.crop.circle.badge.checkmark")
                    .accessibilityIdentifier("settings-signed-in")
                Button(role: .destructive) {
                    Task {
                        await auth.signOut()
                        await store.restore()
                    }
                } label: {
                    Text("Sign out")
                }
                .accessibilityIdentifier("settings-sign-out")
            } else {
                Label("Signed out", systemImage: "person.crop.circle.badge.xmark")
                    .accessibilityIdentifier("settings-signed-out")
                Button {
                    Task {
                        // HB-029: re-entry guard; a fake session cannot
                        // produce real tokens, so say so instead of silently
                        // no-op'ing.
                        let isLive = auth is GoogleSignInAuthSession
                        if !isLive {
                            signInNotice = "Sign-in isn't available in this session."
                            return
                        }
                        guard !isSigningIn else { return }
                        isSigningIn = true
                        defer { isSigningIn = false }
                        if await (auth as? GoogleSignInAuthSession)?.signIn() == true {
                            signInNotice = nil
                            await store.restore()
                        }
                    }
                } label: {
                    if isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Signing in…")
                        }
                    } else {
                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("settings-sign-in")
            }
            Text("Sign out keeps your local history, saves, and downloaded videos on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let signInNotice {
                Text(signInNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var principlesSection: some View {
        Section("FocusTube") {
            Label("Deliberate long-form viewing", systemImage: "play.rectangle")
            Label("No Shorts — filtered before render", systemImage: "slash.circle")
            Label("Subscription feed only, no recommendations", systemImage: "list.bullet.rectangle")
            Label("Explicit load-more, no infinite scrolling", systemImage: "arrow.down.to.line")
        }
    }

    private var downloadPolicySection: some View {
        Section("Downloads") {
            Label("Qualities: 1080p / 720p / 480p / 360p — exact ladder, never higher", systemImage: "arrow.down.circle")
            Label("Wi-Fi required by default; cellular off", systemImage: "wifi")
            Label("Up to two downloads at once; the rest wait in queue", systemImage: "2.square.stack")
            Label("Paused transfers are not supported — cancel and retry instead", systemImage: "pause.slash")
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            let summaries = library.downloaded.map { media in
                OfflineMediaSummary(
                    id: media.id,
                    title: media.title,
                    channelTitle: media.channelTitle ?? "",
                    resolution: media.resolution,
                    sizeBytes: media.sizeBytes,
                    createdAt: media.createdAt
                )
            }
            let total = OfflineLibraryPolicy.totalBytes(summaries)
            Label(
                "Offline videos use \(OfflineLibraryPolicy.formattedFileSize(total)) across \(summaries.count) video\(summaries.count == 1 ? "" : "s"). Manage them in the Downloads tab.",
                systemImage: "internaldrive"
            )
            .accessibilityIdentifier("settings-storage-summary")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("Everything stays on this device", systemImage: "lock.iphone")
            Label("No analytics, ads, or telemetry", systemImage: "eye.slash")
            Label("Only the Google scopes the features need", systemImage: "key")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
                .accessibilityIdentifier("settings-version")
        }
    }
}
