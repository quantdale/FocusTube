public protocol MediaExtracting: Sendable {
    func resolve(videoID: String) async throws -> ResolvedMedia
}
