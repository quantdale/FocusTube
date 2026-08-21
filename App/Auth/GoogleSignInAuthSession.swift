import Foundation
import GoogleSignIn
import os

/// Concrete GoogleSignIn adapter. Keeps the GoogleSignIn surface behind the
/// `AuthSession` boundary. No token is ever printed, logged, or persisted
/// outside the secure GoogleSignIn store.
///
/// GoogleSignIn 9.x exposes a single argument-less `configure()` (async
/// throws) that reads `GIDClientID` from Info.plist. Without that key the
/// adapter stays inert — typed nil/false results instead of the unconfigured-
/// use crash — and real sign-in steps live in PERSONAL_RELEASE_CHECKLIST.md.
public final class GoogleSignInAuthSession: AuthSession {
    /// One-shot configuration claim for the shared GIDSignIn instance
    /// (RootView constructs several session instances). A plain static var
    /// would be non-concurrency-safe global mutable state, hence the lock.
    private static let configured = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Configures the shared instance exactly once; subsequent callers await
    /// the same outcome. Returns whether GoogleSignIn is usable.
    private static func ensureConfigured() async -> Bool {
        if configured.withLock({ $0 }) { return true }
        let hasClientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") != nil
        guard hasClientID else { return false }
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

    public var isAuthenticated: Bool {
        get async { await restore() }
    }

    @discardableResult
    public func restore() async -> Bool {
        guard await Self.ensureConfigured() else { return false }
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                continuation.resume(returning: user != nil && error == nil)
            }
        }
    }

    public func accessToken() async -> String? {
        guard await Self.ensureConfigured() else { return nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
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
