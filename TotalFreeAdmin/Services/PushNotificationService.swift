import UIKit
import UserNotifications

// Registers the device's APNs token in the Supabase `device_tokens` table after
// sign-in. The `send-push` edge function reads that table (platform = 'ios') and
// delivers notifications using `ca.totalfree.admin` as the apns-topic, so the
// app bundle id MUST match the function's APNS_BUNDLE_ID secret.
final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    private weak var appState: AppState?
    private let tokenKey = "ca.totalfree.app.apnsDeviceToken"

    var currentDeviceToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    var apnsEnvironment: String {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "TotalFreeAPNSEnvironment") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if configured == "production" { return "production" }
        if configured == "development" || configured == "sandbox" { return "sandbox" }
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    var bundleId: String {
        Bundle.main.bundleIdentifier ?? "ca.totalfree.admin"
    }

    @MainActor
    func configure(appState: AppState) {
        self.appState = appState
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            appState?.recordPushRegistrationFailure(error.localizedDescription)
        }
    }

    @MainActor
    func registerStoredTokenIfAvailable() async {
        guard let currentDeviceToken else { return }
        await appState?.registerPushDeviceToken(currentDeviceToken)
    }

    @MainActor
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await appState?.registerPushDeviceToken(token) }
    }

    @MainActor
    func didFailToRegisterForRemoteNotifications(error: Error) {
        appState?.recordPushRegistrationFailure(error.localizedDescription)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
