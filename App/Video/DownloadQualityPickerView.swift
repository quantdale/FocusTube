import SwiftUI
import FocusTubeCore

/// HB-024: the download-quality lifecycle has THREE truthful states —
/// resolution in flight, resolution failed, and genuinely no downloadable
/// qualities. Collapsing them into one string lied about which was which.
enum QualityResolutionState: Equatable {
    case resolving
    case failed
    case loaded
}

/// Picker limited to the qualities actually present in resolved media.
struct DownloadQualityPickerView: View {
    let available: [DownloadQuality]
    @Binding var selection: DownloadQuality?
    let state: QualityResolutionState

    var body: some View {
        switch state {
        case .resolving:
            Label("Checking downloadable qualities…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Label(
                "Couldn't check downloadable qualities. Try reopening this video.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .loaded:
            if available.isEmpty {
                Text("No downloadable qualities for this video")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Quality", selection: $selection) {
                    ForEach(available, id: \.self) { quality in
                        Text("\(quality.rawValue)p").tag(quality as DownloadQuality?)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
