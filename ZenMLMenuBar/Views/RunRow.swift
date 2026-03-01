import SwiftUI

struct RunRow: View {
    @Environment(PipelineRunStore.self) private var store
    let run: PipelineRun

    @State private var isHovered = false

    var body: some View {
        Button {
            store.openRunInDashboard(run)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(run.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    StatusPill(status: run.status)
                }

                HStack(spacing: 5) {
                    Text(run.ageText)
                    Text("•")
                    Text(run.durationText)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var rowBackground: some ShapeStyle {
        let base = Color(NSColor.windowBackgroundColor)
        if isHovered {
            return AnyShapeStyle(base.opacity(0.8))
        }
        return AnyShapeStyle(base.opacity(0.45))
    }

    private var borderColor: Color {
        if isHovered {
            return .accentColor.opacity(0.25)
        }
        return .secondary.opacity(0.15)
    }
}

private struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: RunStatus

    @State private var pulse = false

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
            .opacity(status == .running ? (pulse ? 0.6 : 1.0) : 1.0)
            .onAppear {
                guard status == .running else {
                    return
                }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }

    private var foregroundColor: Color {
        switch status {
        case .running, .initializing, .provisioning, .retrying, .stopping:
            return Color(red: 0.2, green: 0.5, blue: 1.0)
        case .failed:
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .completed:
            return Color(red: 0.15, green: 0.65, blue: 0.3)
        case .cached, .retried, .stopped:
            return colorScheme == .dark ? .gray : .secondary
        case .unknown(_):
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .running, .initializing, .provisioning, .retrying, .stopping:
            return Color(red: 0.2, green: 0.5, blue: 1.0).opacity(colorScheme == .dark ? 0.16 : 0.10)
        case .failed:
            return Color(red: 0.9, green: 0.2, blue: 0.2).opacity(colorScheme == .dark ? 0.18 : 0.10)
        case .completed:
            return Color(red: 0.15, green: 0.65, blue: 0.3).opacity(colorScheme == .dark ? 0.18 : 0.10)
        case .cached, .retried, .stopped:
            return .gray.opacity(colorScheme == .dark ? 0.18 : 0.10)
        case .unknown(_):
            return .gray.opacity(0.10)
        }
    }
}
