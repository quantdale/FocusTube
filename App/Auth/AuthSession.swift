import Foundation

/// Authentication boundary. Decouples feature code from GoogleSignIn so the
/// concrete OAuth adapter can be swapped for a fake in deterministic tests and
/// so media extraction is never coupled to auth. Tokens are never logged.
public protocol AuthSession: Sendable {
    var isAuthenticated: Bool { get async }
    /// Restores a previous sign-in if a valid refresh token exists.
    @discardableResult func restore() async -> Bool
    /// Current OAuth access token, or `nil` when unauthenticated.
    func accessToken() async -> String?
    func signOut() async
}

/// Fake used in deterministic tests and as a safe default when no development
/// credentials are configured.
public struct FakeAuthSession: AuthSession {
    public var token: String?
    public var authenticated: Bool

    public init(token: String? = "fake-access-token", authenticated: Bool = true) {
        self.token = token
        self.authenticated = authenticated
    }

    public var isAuthenticated: Bool { get async { authenticated } }
    public func restore() async -> Bool { authenticated }
    public func accessToken() async -> String? { token }
    public func signOut() async {}
}
