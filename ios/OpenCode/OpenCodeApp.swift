import SwiftUI

@main struct OpenCodeApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .task {
                    let process = ProcessInfo.processInfo
                    if !process.arguments.contains("--ui-testing") && process.environment["XCTestConfigurationFilePath"] == nil { await store.start() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.foreground() } }
                    if phase == .background { store.background() }
                }
        }
    }
}
