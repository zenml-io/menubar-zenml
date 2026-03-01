import AppKit
import SwiftUI

struct ConnectionStrip: View {
    @Environment(PipelineRunStore.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(healthDotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.serverName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(store.projectName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if NSImage(named: "ZenMLLogo") != nil {
                Image("ZenMLLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                    .opacity(0.85)
                    .accessibilityHidden(true)
            } else {
                Text("ZenML")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var healthDotColor: Color {
        switch store.connectionState {
        case .connected, .staleRefreshing, .empty:
            return .green
        case .disconnected:
            return .gray
        case .serverError:
            return .orange
        case .loading:
            return .gray.opacity(0.6)
        }
    }
}
