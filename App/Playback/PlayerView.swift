import SwiftUI
import Observation
import FocusTubeCore

/// ADR-0007 player surface: the official IFrame player (WKWebView) plus
/// loading/failure overlays and the deterministic UI-test markers.
public struct PlayerView: View {
    @Bindable var coordinator: PlayerCoordinator
    @Environment(\.openURL) private var openURL

    public init(coordinator: PlayerCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            if let web = coordinator.engine as? WKWebViewPlayerEngine {
                IFramePlayerView(engine: web)
            } else {
                Color.black
            }

            switch coordinator.state.status {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.35))
                    .allowsHitTesting(false)
            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Playback failed")
                        .font(.headline)
                    Text(failureDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                        if coordinator.iframeError?.isRetryable ?? true {
                            Button("Retry") {
                                if let id = coordinator.currentVideoID {
                                    Task { await coordinator.loadAndPlay(videoID: id) }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if let id = coordinator.currentVideoID,
                           let url = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                            Button("Open in YouTube") { openURL(url) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
            default:
                EmptyView()
            }

            // Deterministic markers for UI journeys (HB-014): `player-status`
            // always exposes the live state; `player-playing` only when playing.
            VStack {
                HStack {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("player-status")
                        .accessibilityLabel(String(describing: coordinator.state.status))
                    if coordinator.state.status == .playing {
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 44, height: 44)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("player-playing")
                    }
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .frame(height: 240)
    }

    private var failureDetail: String {
        switch coordinator.iframeError {
        case .embeddingNotAllowed?: return "The owner doesn't allow this video to play outside YouTube."
        case .videoNotFound?: return "This video is unavailable."
        case .html5Error?: return "The player hit an error. Try again."
        case .invalidParameter?: return "This video can't be played."
        case .unknown(let code)?: return "Player error \(code)."
        case nil: return coordinator.state.error.map { String(describing: $0) } ?? ""
        }
    }
}
