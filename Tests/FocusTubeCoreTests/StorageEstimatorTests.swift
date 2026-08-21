import Testing
@testable import FocusTubeCore

/// Deterministic coverage for the conservative free-space admission estimates
/// introduced with the storage-floor hardening (HB-009).
@Test func unknownDurationEstimatesToZero() {
    #expect(StorageEstimator.requiredBytes(resolution: 720, durationSeconds: 0, componentCount: 1) == 0)
    #expect(StorageEstimator.requiredBytes(resolution: 1080, durationSeconds: -5, componentCount: 2) == 0)
}

@Test func estimateScalesLinearlyWithDuration() {
    let oneMinute = StorageEstimator.requiredBytes(resolution: 720, durationSeconds: 60, componentCount: 1)
    let twoMinutes = StorageEstimator.requiredBytes(resolution: 720, durationSeconds: 120, componentCount: 1)
    #expect(twoMinutes == 2 * oneMinute)
    #expect(oneMinute > 0)
}

@Test func tiersAreMonotonicallyLarger() {
    let duration = 600.0
    let p360 = StorageEstimator.requiredBytes(resolution: 360, durationSeconds: duration, componentCount: 1)
    let p480 = StorageEstimator.requiredBytes(resolution: 480, durationSeconds: duration, componentCount: 1)
    let p720 = StorageEstimator.requiredBytes(resolution: 720, durationSeconds: duration, componentCount: 1)
    let p1080 = StorageEstimator.requiredBytes(resolution: 1080, durationSeconds: duration, componentCount: 1)
    #expect(p360 < p480)
    #expect(p480 < p720)
    #expect(p720 < p1080)
}

@Test func adaptiveCarriesTransientHeadroom() {
    // Two components plus the muxed output coexist on disk, so the adaptive
    // estimate must exceed the combined estimate for the same tier/duration.
    let combined = StorageEstimator.requiredBytes(resolution: 1080, durationSeconds: 300, componentCount: 1)
    let adaptive = StorageEstimator.requiredBytes(resolution: 1080, durationSeconds: 300, componentCount: 2)
    #expect(adaptive > combined)
}
