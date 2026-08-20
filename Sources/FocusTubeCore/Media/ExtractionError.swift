public enum ExtractionError: Error, Equatable, Sendable {
    case unavailable
    case restricted
    case extractorIncompatible
    case noAllowedQuality
    case transientNetwork
    case malformedResponse
    case unknown
}
