import SwiftUI
import AVKit
import Observation
import FocusTubeCore

/// SwiftUI wrapper around the system `AVPlayerViewController`. The controller is
/// owned by the `PlayerCoordinator` and injected, so SwiftUI view recreation
/// does not reconstruct or reset the player.
public struct PlayerViewControllerRepresentation: UIViewControllerRepresentable {
    let controller: AVPlayerViewController

    public init(controller: AVPlayerViewController) {
        self.controller = controller
    }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        controller
    }

    public func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

/// High-level player surface: native `AVPlayerViewController` plus overlay
/// states for loading and typed failures.
public struct PlayerView: View {
    @Bindable var coordinator: PlayerCoordinator

    public init(coordinator: PlayerCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            PlayerViewControllerRepresentation(controller: coordinator.playerViewController)

            switch coordinator.state.status {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.35))
            case .failed:
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Playback failed")
                        .font(.headline)
                    if let error = coordinator.state.error {
                        Text(String(describing: error))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry") {
                        if let id = coordinator.currentVideoID {
                            Task { await coordinator.loadAndPlay(videoID: id) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.6))
                .foregroundStyle(.white)
            default:
                EmptyView()
            }
        }
        // Hard internal bound: overlay states propose unbounded flexible
        // frames, and an unconstrained ZStack lets them inflate the hosting
        // List row (pushing every following section below the lazy-render
        // fold) on current iOS runtimes. The caller applies the same height;
        // this makes the contract local to the player surface.
        .frame(height: 240)
    }
}
