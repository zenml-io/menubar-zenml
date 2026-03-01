import SwiftUI

struct MenuBarIcon: View {
    @Environment(PipelineRunStore.self) private var store

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .overlay(alignment: .topTrailing) {
                if store.hasUnacknowledgedFailures && !store.isDisconnected {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -3)
                }
            }
            .accessibilityLabel("ZenML pipeline status")
    }

    private var symbolName: String {
        if store.isDisconnected {
            return "wifi.slash"
        }
        if store.hasUnacknowledgedFailures {
            return "exclamationmark.triangle"
        }
        return "point.3.connected.trianglepath.dotted"
    }
}
