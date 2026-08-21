import Foundation
import GoogleSignIn

/// Concrete GoogleSignIn adapter. Keeps the GoogleSignIn surface behind the
/// `AuthSession` boundary. No token is ever printed, logged, or persisted
/// outside the secure GoogleSignIn store. Uses the stable closure-based
/// `GIDSignIn` API wrapped in continuations.
public final class GoogleSignInAuthSession: AuthSession {
    /// Guards one-time global configuration of the shared GIDSignIn instance
    /// (RootView constructs several session instances).
    private static let configurationLock = NSLock()
    private static var hasConfiguredGIDSignIn = false

    /// True only when a `GIDClientID` was found in Info.plist. Without it the
    /// GoogleSignIn surface stays inert (typed nil/false results) instead of
    /// crashing on unconfigured use; real sign-in requires the owner to add
    /// the client id (see PERSONAL_RELEASE_CHECKLIST.md).
    private let isConfigured: Bool

    public init(clientID: String? = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) {
        Self.configurationLock.lock()
        defer { Self.configurationLock.unlock() }
        if let clientID, !Self.hasConfiguredGIDSignIn {
            GIDSignIn.sharedInstance.configure(clientID: clientID)
            Self.hasConfiguredGIDSignIn = true
        }
        self.isConfigured = Self.hasConfiguredGIDSignIn
    }

    public var isAuthenticated: Bool {
        get async { await restore() }
    }

    @discardableResult
    public func restore() async -> Bool {
        guard isConfigured else { return false }
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                continuation.resume(returning: user != nil && error == nil)
            }
        }
    }

    public func accessToken() async -> String? {
        guard isConfigured else { return nil }
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user, error == nil {
                    // GoogleSignIn 9.x: accessToken is non-optional GIDToken.
                    continuation.resume(returning: user.accessToken.tokenString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func signOut() async {
        guard isConfigured else { return }
        GIDSignIn.sharedInstance.signOut()
    }
}
