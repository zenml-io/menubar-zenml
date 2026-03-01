import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(PipelineRunStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            ConnectionStrip()

            if let bannerText = store.bannerText {
                Text(bannerText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08))
            }

            Group {
                if store.isServerError {
                    ErrorStateView(message: store.connectionReason ?? "The server returned an error.")
                } else if store.displayedRuns.isEmpty, store.connectionState == .empty {
                    EmptyStateView()
                } else if store.displayedRuns.isEmpty, store.connectionState == .loading {
                    ProgressView("Loading ZenML runs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RunListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Text(store.footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            store.startIfNeeded()
            store.acknowledgeFailures()
        }
    }
}
