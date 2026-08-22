import XCTest
import os
@testable import FocusTube
import FocusTubeCore

final class AuthSessionTests: XCTestCase {
    func testFakeAuthSessionReturnsTokenWhenAuthenticated() async {
        let session = FakeAuthSession(token: "tok-123", authenticated: true)
        // Bind async results before assertions; XCTest autoclosures do not
        // support await.
        let authenticated = await session.isAuthenticated
        XCTAssertTrue(authenticated)
        let token = await session.accessToken()
        XCTAssertEqual(token, "tok-123")
        let restored = await session.restore()
        XCTAssertTrue(restored)
    }

    func testFakeAuthSessionUnauthenticated() async {
        let session = FakeAuthSession(token: nil, authenticated: false)
        let authenticated = await session.isAuthenticated
        XCTAssertFalse(authenticated)
        let token = await session.accessToken()
        XCTAssertNil(token)
    }

    func testAuthSessionTypeIsSendable() {
        let session: FakeAuthSession = FakeAuthSession()
        // Compile-time Sendable confirmation: stored in a Sendable context.
        let _: any AuthSession = session
    }

    // MARK: - ConfigCoordinator single-flight behavior (DEBUG)

    #if DEBUG
    /// Counting operation recording how many times configuration ran.
    private final class ConfigCounter: @unchecked Sendable {
        enum ConfigError: Error { case failed }

        private let lock = OSAllocatedUnfairLock<ConfigCounter.State>(initialState: State())

        private struct State {
            var startCount = 0
            var shouldSucceed = true
        }

        /// The operation under test: counts each start, succeeds or throws
        /// according to `shouldSucceed`.
        lazy var operation: @Sendable () async throws -> Void = { [self] in
            lock.withLock { $0.startCount += 1 }
            let succeed = lock.withLock { $0.shouldSucceed }
            guard succeed else { throw ConfigError.failed }
        }

        var startCount: Int { lock.withLock { $0.startCount } }

        func setShouldSucceed(_ value: Bool) {
            lock.withLock { $0.shouldSucceed = value }
        }
    }

    func testConcurrentConfigureRunsOperationOnceAndAllCallersSucceed() async {
        let counter = ConfigCounter()
        await GoogleSignInAuthSession._resetConfigForTesting(operation: counter.operation)
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<8 {
                group.addTask {
                    await GoogleSignInAuthSession._ensureConfiguredForTesting()
                }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }
        XCTAssertEqual(results.count, 8)
        // Single flight: exactly one operation run, every caller sees success.
        XCTAssertEqual(counter.startCount, 1)
        XCTAssertTrue(results.allSatisfy { $0 })
    }

    func testFailedConfigureReportsFalseToAllThenRetriesOnce() async {
        let operation = GatedConfigOperation()
        operation.setShouldSucceed(false)
        await GoogleSignInAuthSession._resetConfigForTesting(operation: {
            try await operation.run()
        })
        let firstWave = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<8 {
                group.addTask {
                    await GoogleSignInAuthSession._ensureConfiguredForTesting()
                }
            }
            // Deterministic barrier: hold the first attempt open until all
            // eight callers have genuinely arrived — one suspended inside the
            // gated operation, seven parked as waiters on the same attempt —
            // then release the failure. Without this barrier a fail-fast
            // attempt could complete before later tasks enter the actor, and
            // those callers would legitimately start their own retry.
            await GoogleSignInAuthSession._waitUntilConfigWaitersReachForTesting(7)
            operation.releaseFirstAttempt()
            var collected: [Bool] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        XCTAssertEqual(firstWave.count, 8)
        XCTAssertEqual(operation.startCount, 1, "overlapping wave must run exactly one underlying configure attempt")
        XCTAssertFalse(firstWave.contains(true), "every overlapping caller observes the same failure")

        // Failure must not stick: the next call retries the operation.
        operation.setShouldSucceed(true)
        let retry = await GoogleSignInAuthSession._ensureConfiguredForTesting()
        XCTAssertEqual(operation.startCount, 2, "exactly one new attempt after failure")
        XCTAssertTrue(retry)

        // Success sticks: no further retries.
        let again = await GoogleSignInAuthSession._ensureConfiguredForTesting()
        XCTAssertTrue(again)
        XCTAssertEqual(operation.startCount, 2)
    }

    /// One-shot gate: `wait()` suspends until `release()`; releasing before
    /// anyone waits keeps later waits non-suspending. Lock-protected because
    /// the releasing side runs on an arbitrary task executor.
    private final class ReleaseGate: @unchecked Sendable {
        private enum State {
            case idle
            case parked(CheckedContinuation<Void, Never>)
            case released
        }

        private let lock = OSAllocatedUnfairLock<State>(initialState: .idle)

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { state -> CheckedContinuation<Void, Never>? in
                    if case .released = state {
                        return continuation
                    }
                    state = .parked(continuation)
                    return nil
                }
                resumeNow?.resume()
            }
        }

        func release() {
            let parked = lock.withLock { state -> CheckedContinuation<Void, Never>? in
                switch state {
                case .idle:
                    state = .released
                    return nil
                case .parked(let continuation):
                    state = .released
                    return continuation
                case .released:
                    return nil
                }
            }
            parked?.resume()
        }
    }

    /// Counting configuration operation whose attempts block on a one-shot
    /// release gate until the test lets them proceed, then fail or succeed per
    /// `shouldSucceed`. While the first attempt holds the coordinator's
    /// `.configuring` phase open, every concurrent wave caller must park as a
    /// waiter instead of starting its own retry — making single-flight overlap
    /// deterministic rather than executor-timing-dependent.
    private final class GatedConfigOperation: @unchecked Sendable {
        enum OperationError: Error { case failed }

        private struct State {
            var startCount = 0
            var shouldSucceed = true
        }

        private let lock = OSAllocatedUnfairLock<State>(initialState: State())
        private let gate = ReleaseGate()

        var startCount: Int { lock.withLock { $0.startCount } }

        func setShouldSucceed(_ value: Bool) {
            lock.withLock { $0.shouldSucceed = value }
        }

        func releaseFirstAttempt() {
            gate.release()
        }

        /// The operation handed to the coordinator.
        func run() async throws {
            lock.withLock { $0.startCount += 1 }
            await gate.wait()
            let succeed = lock.withLock { $0.shouldSucceed }
            guard succeed else { throw OperationError.failed }
        }
    }
#endif
}
