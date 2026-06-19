import SwiftUI

@main
struct TotalFreeAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accent)
                .task { await appState.restoreSession() }
                .onOpenURL { url in
                    Task { await appState.handleOpenURL(url) }
                }
        }
    }
}
