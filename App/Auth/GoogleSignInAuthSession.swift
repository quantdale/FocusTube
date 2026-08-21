import Foundation
import GoogleSignIn
import UIKit
import os

/// Concrete GoogleSignIn adapter. Keeps the GoogleSignIn surface behind the
/// `AuthSession` boundary. No token is ever printed, logged, or persisted
/// outside the secure GoogleSignIn store.
///
/// GoogleSignIn 9.x exposes a single argument-less `configure()` (async
/// throws) that reads `GIDClientID` from Info.plist. Without that key (or with
/// an empty one from an unwired build) the adapter stays inert — typed
/// nil/false results instead of the unconfigured-use crash.
public final class GoogleSignInAuthSession: AuthSession {
    /// One-shot configuration claim for the shared GIDSignIn instance
    /// (RootView constructs several session instances). A plain static var
    /// would be non-concurrency-safe global mutable state, hence the lock.
    private static let configured = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Configures the shared instance exactly once; subsequent callers await
    /// the same outcome. Returns whether GoogleSignIn is usable.
    private static func ensureConfigured() async -> Bool {
        if configured.withLock({ $0 }) { return true }
        // An unwired build substitutes an empty string for $(GOOGLE_CLIENT_ID)
        // in Info.plist; treat that exactly like an absent key so the adapter
        // stays inert instead of failing inside configure().
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let clientID, !clientID.isEmpty else { return false }
        // Claim the one-shot configure before awaiting; on failure release so
        // a later caller can retry.
        let claimed = configured.withLock { state -> Bool in
            if state { return false }
            state = true
            return true
        }
        guard claimed else {
            // Another caller is configuring right now; give it a moment and
            // report its outcome.
            try? await Task.sleep(nanoseconds: 500_000_000)
            return configured.withLock { $0 }
        }
        do {
            try await GIDSignIn.sharedInstance.configure()
            return true
        } catch {
            os_log("GoogleSignIn configure failed: %{public}@", String(describing: error))
            configured.withLock { $0 = false }
            return false
        }
    }

    public init() {}

    /// YouTube Data API scopes FocusTube's authenticated calls require:
    /// reads (subscriptions, playlist items, videos, search, comments) are
    /// covered by readonly; subscribe/unsubscribe and rating need force-ssl.
    private static let youTubeScopes = [
        "https://www.googleapis.com/auth/youtube.readonly",
        "https://www.googleapis.com/auth/youtube.force-ssl"
    ]

    /// Runs the interactive Google sign-in flow, requesting the YouTube scopes
    /// above. Presents on the foreground scene's topmost view controller so
    /// SwiftUI callers stay UIKit-free. Returns whether a user is signed in
    /// afterwards; false when unconfigured, no scene is available, or the user
    /// cancelled. Tokens remain inside the GoogleSignIn store.
    public func signIn() async -> Bool {
        guard await Self.ensureConfigured() else { return false }
        guard let presenting = Self.topPresentingViewController() else { return false }
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenting,
                hint: nil,
                additionalScopes: Self.youTubeScopes
            ) { result, error in
                continuation.resume(returning: error == nil && result?.user != nil)
            }
        }
    }

    private static func topPresentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    public var isAuthenticated: Bool {
        get async { await restore() }
    }

    @discardableResult
    public func restore() async -> Bool {
        guard await Self.ensureConfigured() else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                continuation.resume(returning: user != nil && error == nil)
            }
        }
    }

    public func accessToken() async -> String? {
        guard await Self.ensureConfigured() else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user, error == nil {
                    continuation.resume(returning: user.accessToken.tokenString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func signOut() async {
        guard await Self.ensureConfigured() else { return }
        GIDSignIn.sharedInstance.signOut()
    }
}
