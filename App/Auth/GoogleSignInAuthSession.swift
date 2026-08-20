import Foundation
import GoogleSignIn

/// Concrete GoogleSignIn adapter. Keeps the GoogleSignIn surface behind the
/// `AuthSession` boundary. No token is ever printed, logged, or persisted
/// outside the secure GoogleSignIn store. Uses the stable closure-based
/// `GIDSignIn` API wrapped in continuations.
public final class GoogleSignInAuthSession: AuthSession {
    public init() {}

    public var isAuthenticated: Bool {
        get async { await restore() }
    }

    @discardableResult
    public func restore() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                continuation.resume(returning: user != nil && error == nil)
            }
        }
    }

    public func accessToken() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user, error == nil {
                    continuation.resume(returning: user.accessToken?.tokenString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func signOut() async {
        GIDSignIn.sharedInstance.signOut()
    }
}
