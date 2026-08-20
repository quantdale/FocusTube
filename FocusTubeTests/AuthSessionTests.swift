import XCTest
@testable import FocusTube
import FocusTubeCore

final class AuthSessionTests: XCTestCase {
    func testFakeAuthSessionReturnsTokenWhenAuthenticated() async {
        let session = FakeAuthSession(token: "tok-123", authenticated: true)
        XCTAssertTrue(await session.isAuthenticated)
        XCTAssertEqual(await session.accessToken(), "tok-123")
        XCTAssertTrue(await session.restore())
    }

    func testFakeAuthSessionUnauthenticated() async {
        let session = FakeAuthSession(token: nil, authenticated: false)
        XCTAssertFalse(await session.isAuthenticated)
        XCTAssertNil(await session.accessToken())
    }

    func testAuthSessionTypeIsSendable() {
        let session: FakeAuthSession = FakeAuthSession()
        // Compile-time Sendable confirmation: stored in a Sendable context.
        let _: any AuthSession = session
    }
}
