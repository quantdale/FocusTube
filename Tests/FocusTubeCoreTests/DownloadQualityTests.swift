import Testing
@testable import FocusTubeCore

@Test func allowedQualityLadderIsLocked() {
    #expect(DownloadQuality.descending.map(\.rawValue) == [1080, 720, 480, 360])
}

@Test func higherThan1080IsNeverSelected() {
    #expect(DownloadQuality.highestAllowed(availableResolutions: [2160, 1440, 1080, 720]) == .p1080)
}

@Test func missingQualitiesAreNotManufactured() {
    #expect(DownloadQuality.highestAllowed(availableResolutions: [720, 360]) == .p720)
}
