import AppKit
import SwiftUI

struct MenuBarIcon: View {
    @Environment(PipelineRunStore.self) private var store

    var body: some View {
        ZStack(alignment: .topTrailing) {
            pipelineGlyph
                .frame(width: 18, height: 14)

            if store.hasUnacknowledgedFailures && !store.isDisconnected {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .offset(x: 3, y: -2)
            }

            if store.isDisconnected {
                Rectangle()
                    .fill(iconColor)
                    .frame(width: 1.4, height: 18)
                    .rotationEffect(.degrees(-35))
                    .offset(x: 0, y: 0)
            }
        }
        .frame(width: 22, height: 16)
        .opacity(store.isDisconnected ? 0.45 : 1.0)
        .accessibilityLabel("ZenML pipeline status")
    }

    private var pipelineGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1)
                .fill(iconColor)
                .frame(width: 1.8, height: 7.8)
                .rotationEffect(.degrees(30))
                .offset(x: -3.4, y: 0.8)

            RoundedRectangle(cornerRadius: 1)
                .fill(iconColor)
                .frame(width: 1.8, height: 7.8)
                .rotationEffect(.degrees(-30))
                .offset(x: 3.4, y: 0.8)

            Circle()
                .fill(iconColor)
                .frame(width: 4.3, height: 4.3)
                .offset(x: 0, y: -4.1)

            Circle()
                .fill(iconColor)
                .frame(width: 4.3, height: 4.3)
                .offset(x: -5.2, y: 4.0)

            Circle()
                .fill(iconColor)
                .frame(width: 4.3, height: 4.3)
                .offset(x: 5.2, y: 4.0)
        }
    }

    private var iconColor: Color {
        Color(nsColor: .labelColor)
    }
}
