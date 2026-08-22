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
    /// Single-flight coordinator for configuring the shared GIDSignIn
    /// instance (RootView constructs several session instances). Concurrent
    /// callers either observe the cached outcome or await the in-flight
    /// configure as proper continuations — no polling, no premature claims.
    private actor ConfigCoordinator {
        enum Phase { case unconfigured, configuring, configured, failed }
        private var phase = Phase.unconfigured
        private var waiters: [CheckedContinuation<Bool, Never>] = []
        private let operation: @Sendable () async throws -> Void
#if DEBUG
        /// Deterministic-barrier registrations for the single-flight overlap
        /// test: each watcher resumes once `waiters.count >= threshold`.
        private var waiterThresholdWatchers: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []
#endif

        init(operation: @escaping @Sendable () async throws -> Void) {
            self.operation = operation
        }

        /// Runs `operation` at most once per success window; returns whether
        /// configuration ended up usable. Failed attempts reset to `.failed`
        /// so a later call retries.
        func configured() async -> Bool {
            switch phase {
            case .configured:
                return true
            case .configuring:
                // Suspend until the in-flight attempt resolves; every waiter
                // receives the same outcome.
                return await withCheckedContinuation { continuation in
                    waiters.append(continuation)
#if DEBUG
                    fireWaiterThresholdWatchers()
#endif
                }
            case .unconfigured, .failed:
                phase = .configuring
                do {
                    try await operation()
                    phase = .configured
                } catch {
                    // Private-default: error text may embed request context.
                    Logger(subsystem: "com.focustube.app", category: "auth")
                        .error("GoogleSignIn configure failed: \(String(describing: error), privacy: .private)")
                    phase = .failed
                }
                let ok = phase == .configured
                waiters.forEach { $0.resume(returning: ok) }
                waiters.removeAll()
                return ok
            }
        }

#if DEBUG
        /// DEBUG-only deterministic barrier for the overlap test: resumes once
        /// at least `threshold` concurrent callers are parked awaiting the
        /// in-flight configuration attempt. Event-driven via continuations —
        /// no polling and no sleeps anywhere.
        func notifyWhenWaitersReach(_ threshold: Int) async {
            guard waiters.count < threshold else { return }
            await withCheckedContinuation { continuation in
                waiterThresholdWatchers.append((threshold, continuation))
            }
        }

        private func fireWaiterThresholdWatchers() {
            guard !waiterThresholdWatchers.isEmpty else { return }
            var fired: [CheckedContinuation<Void, Never>] = []
            waiterThresholdWatchers.removeAll { watcher in
                if waiters.count >= watcher.threshold {
                    fired.append(watcher.continuation)
                    return true
                }
                return false
            }
            for continuation in fired {
                continuation.resume()
            }
        }
#endif
    }

#if DEBUG
    /// Test seam. `nonisolated(unsafe)` because access is confined by
    /// convention: written only from MainActor test code via
    /// `_resetConfigForTesting`, read once during static initialization;
    /// production code never touches it.
    private static nonisolated(unsafe) var _configCoordinatorForTesting: ConfigCoordinator?

    private static let configCoordinatorDefault = ConfigCoordinator(operation: {
        try await GIDSignIn.sharedInstance.configure()
    })

    private static var configCoordinator: ConfigCoordinator {
        if let coordinator = _configCoordinatorForTesting { return coordinator }
        return configCoordinatorDefault
    }

    /// DEBUG-only hook for deterministic tests of the single-flight behavior.
    @MainActor
    static func _resetConfigForTesting(operation: @escaping @Sendable () async throws -> Void) {
        _configCoordinatorForTesting = ConfigCoordinator(operation: operation)
    }

    /// Test entry that bypasses the Info.plist clientID guard so the
    /// coordinator itself can be exercised deterministically.
    static func _ensureConfiguredForTesting() async -> Bool {
        await configCoordinator.configured()
    }

    /// DEBUG-only deterministic barrier: resumes exactly when `threshold`
    /// concurrent callers are parked awaiting the same in-flight configuration
    /// attempt. Lets tests prove genuine overlap instead of guessing at
    /// executor timing.
    static func _waitUntilConfigWaitersReachForTesting(_ threshold: Int) async {
        await configCoordinator.notifyWhenWaitersReach(threshold)
    }
#else
    private static let configCoordinator = ConfigCoordinator(operation: {
        try await GIDSignIn.sharedInstance.configure()
    })
#endif

    /// Configures the shared instance exactly once; subsequent callers await
    /// the same outcome. Returns whether GoogleSignIn is usable.
    private static func ensureConfigured() async -> Bool {
        // An unwired build substitutes an empty string for $(GOOGLE_CLIENT_ID)
        // in Info.plist; treat that exactly like an absent key so the adapter
        // stays inert instead of failing inside configure().
        let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let clientID, !clientID.isEmpty else { return false }
        return await configCoordinator.configured()
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
    /// MainActor-isolated because it resolves the presenting UI.
    @MainActor
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

    @MainActor
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
