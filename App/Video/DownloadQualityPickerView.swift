import SwiftUI
import FocusTubeCore

/// Picker limited to the qualities actually present in resolved media.
struct DownloadQualityPickerView: View {
    let available: [DownloadQuality]
    @Binding var selection: DownloadQuality?

    var body: some View {
        if available.isEmpty {
            Text("No downloadable qualities available")
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
