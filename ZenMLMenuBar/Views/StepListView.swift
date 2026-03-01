import SwiftUI

struct StepListView: View {
    let steps: [StepRun]
    let maxInlineCount: Int
    let openAllInDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { _, step in
                HStack(spacing: 8) {
                    StepStatusDot(status: step.status)

                    Text(step.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !step.durationText.isEmpty {
                        Text(step.durationText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if orderedSteps.count > maxInlineCount {
                Button {
                    openAllInDashboard()
                } label: {
                    Text("Show all \(orderedSteps.count) steps in Dashboard →")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var orderedSteps: [StepRun] {
        steps.sorted { lhs, rhs in
            switch (lhs.startTime, rhs.startTime) {
            case let (lhsTime?, rhsTime?):
                return lhsTime < rhsTime
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var visibleSteps: [StepRun] {
        Array(orderedSteps.prefix(maxInlineCount))
    }
}
