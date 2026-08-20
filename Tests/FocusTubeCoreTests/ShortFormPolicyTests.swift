import Testing
@testable import FocusTubeCore

@Test func shortFormDurationBoundaryIsConservative() {
    let policy = ShortFormPolicy()
    #expect(policy.isBlocked(durationSeconds: 180))
    #expect(!policy.isBlocked(durationSeconds: 181))
}

@Test func shortsRouteIsBlocked() {
    let policy = ShortFormPolicy()
    #expect(policy.isBlocked(urlPath: "/shorts/abc123"))
    #expect(!policy.isBlocked(urlPath: "/watch?v=abc123"))
}
