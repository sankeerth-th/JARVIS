import SwiftUI
import AppIntents

@main
struct JarvisIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appModel = JarvisPhoneAppModel()

    init() {
        JarvisPhoneShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            JarvisPhoneRootView()
                .environmentObject(appModel)
                .onOpenURL { url in
                    appModel.handleIncomingURL(url)
                }
                .task {
                    appModel.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    appModel.handleScenePhase(newPhase)
                }
        }
    }
}
