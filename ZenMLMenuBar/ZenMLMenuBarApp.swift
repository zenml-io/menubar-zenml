import SwiftUI

@main
struct ZenMLMenuBarApp: App {
    @State private var store = PipelineRunStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .frame(width: 320, height: 520)
                .environment(store)
                .task {
                    store.startIfNeeded()
                }
        } label: {
            MenuBarIcon()
                .environment(store)
                .task {
                    store.startIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
