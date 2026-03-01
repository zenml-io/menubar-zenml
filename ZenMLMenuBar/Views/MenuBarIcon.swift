import SwiftUI

struct MenuBarIcon: View {
    @Environment(PipelineRunStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

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
                    .frame(width: 1.3, height: 18)
                    .rotationEffect(.degrees(-35))
                    .offset(x: 0, y: 0)
            }
        }
        .frame(width: 22, height: 16)
        .opacity(store.isDisconnected ? 0.35 : 1.0)
        .accessibilityLabel("ZenML pipeline status")
    }

    private var pipelineGlyph: some View {
        Canvas { context, size in
            let nodeRadius: CGFloat = 1.6
            let lineWidth: CGFloat = 1.3

            let top = CGPoint(x: size.width * 0.5, y: size.height * 0.2)
            let left = CGPoint(x: size.width * 0.23, y: size.height * 0.8)
            let right = CGPoint(x: size.width * 0.77, y: size.height * 0.8)

            var lines = Path()
            lines.move(to: top)
            lines.addLine(to: left)
            lines.move(to: top)
            lines.addLine(to: right)
            context.stroke(lines, with: .color(iconColor), lineWidth: lineWidth)

            let points = [top, left, right]
            for point in points {
                let nodeRect = CGRect(
                    x: point.x - nodeRadius,
                    y: point.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                let nodePath = Path(ellipseIn: nodeRect)
                context.fill(nodePath, with: .color(iconColor))
            }
        }
    }

    private var iconColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12)
    }
}
