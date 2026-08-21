import XCTest
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
}
