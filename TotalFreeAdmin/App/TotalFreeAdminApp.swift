import SwiftUI

@main
struct TotalFreeAdminApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @AppStorage("app.appearance") private var appearanceRaw = AppAppearance.bright.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .bright
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
                .task { await appState.restoreSession() }
                .onOpenURL { url in
                    Task { await appState.handleOpenURL(url) }
                }
        }
    }
}
