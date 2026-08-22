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
        let counter = ConfigCounter()
        counter.setShouldSucceed(false)
        await GoogleSignInAuthSession._resetConfigForTesting(operation: counter.operation)
        let firstWave = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<8 {
                group.addTask {
                    await GoogleSignInAuthSession._ensureConfiguredForTesting()
                }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }
        XCTAssertEqual(firstWave.count, 8)
        XCTAssertEqual(counter.startCount, 1)
        XCTAssertFalse(firstWave.contains(true))

        // Failure must not stick: the next call retries the operation.
        counter.setShouldSucceed(true)
        let retry = await GoogleSignInAuthSession._ensureConfiguredForTesting()
        XCTAssertEqual(counter.startCount, 2)
        XCTAssertTrue(retry)

        // Success sticks: no further retries.
        let again = await GoogleSignInAuthSession._ensureConfiguredForTesting()
        XCTAssertTrue(again)
        XCTAssertEqual(counter.startCount, 2)
    }
    #endif
}
