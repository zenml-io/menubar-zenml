import SwiftUI

struct StepStatusDot: View {
    let status: RunStatus

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(fillColor)
            .overlay(
                Circle()
                    .strokeBorder(strokeColor, lineWidth: isPendingLike ? 1 : 0)
            )
            .frame(width: 8, height: 8)
            .scaleEffect(status == .running && pulse ? 1.2 : 1.0)
            .opacity(status == .running ? (pulse ? 0.55 : 1.0) : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear {
                guard status == .running else {
                    return
                }
                pulse = true
            }
    }

    private var isPendingLike: Bool {
        switch status {
        case .completed, .failed, .running:
            return false
        default:
            return true
        }
    }

    private var fillColor: Color {
        switch status {
        case .completed:
            return Color(red: 0.15, green: 0.65, blue: 0.3)
        case .failed:
            return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .running:
            return Color(red: 0.2, green: 0.5, blue: 1.0)
        default:
            return .clear
        }
    }

    private var strokeColor: Color {
        if isPendingLike {
            return .secondary.opacity(0.6)
        }
        return .clear
    }
}
