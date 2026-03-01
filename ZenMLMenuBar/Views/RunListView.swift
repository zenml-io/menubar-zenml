import SwiftUI

struct RunListView: View {
    @Environment(PipelineRunStore.self) private var store

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !store.inProgressRuns.isEmpty {
                        section(title: "In Progress", runs: store.inProgressRuns)
                    }

                    if !store.failedRuns.isEmpty {
                        section(title: "Failed", runs: store.failedRuns)
                    }

                    if !store.recentRuns.isEmpty {
                        section(title: "Recent", runs: store.recentRuns)
                    }
                }
                .padding(12)
            }
            .opacity(store.shouldDimRunList ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: store.shouldDimRunList)

            if store.shouldShowRefreshingOverlay {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Refreshing…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(radius: 4)
            }
        }
    }

    @ViewBuilder
    private func section(title: String, runs: [PipelineRun]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.4)

            VStack(spacing: 6) {
                ForEach(runs) { run in
                    RunRow(run: run)
                }
            }
        }
    }
}
