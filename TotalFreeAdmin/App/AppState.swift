import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var me: MeResponse?
    @Published private(set) var dashboard: AdminDashboard?
    @Published private(set) var users: [AdminUser] = []
    @Published var isBusy = false
    @Published var alertMessage: String?

    private let sessionStore: SessionStoring
    private let apiBaseURL = URL(string: "https://total-free-api.hurryupgo-b2d.workers.dev")!

    init(sessionStore: SessionStoring = KeychainSessionStore()) {
        self.sessionStore = sessionStore
        PushNotificationService.shared.configure(appState: self)
    }

    var role: StaffRole {
        me?.profile?.role ?? .member
    }

    var canUseAdminApp: Bool {
        me?.profile?.status == .active && role.isStaff
    }

    var client: TotalFreeAPIClient {
        TotalFreeAPIClient(baseURL: apiBaseURL, accessToken: session?.accessToken)
    }

    func restoreSession() async {
        guard session == nil, let stored = sessionStore.load() else { return }
        session = stored
        await loadMe()
        if canUseAdminApp {
            await refreshDashboard()
            await enablePushNotifications()
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let login: AuthSession = try await TotalFreeAPIClient(baseURL: apiBaseURL)
                .post("/api/auth/login", body: LoginRequest(email: email, password: password))
            session = login
            try sessionStore.save(login)
            await loadMe()
            guard canUseAdminApp else {
                throw APIClientError.server("Admin access required for this app.")
            }
            await refreshDashboard()
            await enablePushNotifications()
        }
    }

    func signOut() {
        let signOutClient = client
        if let token = PushNotificationService.shared.currentDeviceToken {
            Task {
                let _: EmptyResponse? = try? await signOutClient.delete("/api/push/devices/\(token)")
            }
        }
        sessionStore.clear()
        session = nil
        me = nil
        dashboard = nil
        users = []
    }

    func loadMe() async {
        do {
            me = try await client.get("/api/me")
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func refreshDashboard() async {
        await run {
            dashboard = try await client.get("/api/admin/dashboard")
        }
    }

    func fetchPostDetail(id: String) async throws -> AdminPostDetail {
        let response: AdminPostDetailResponse = try await client.get("/api/admin/posts/\(id)")
        return response.item
    }

    func fetchReportDetail(id: String) async throws -> AdminReportDetailResponse {
        try await client.get("/api/admin/reports/\(id)")
    }

    func approve(post: PendingPost) async {
        await approvePost(id: post.id)
    }

    func approve(post: AdminPostDetail) async {
        await approvePost(id: post.id)
    }

    func approvePost(id: String) async {
        await run {
            let _: EmptyResponse = try await client.post("/api/admin/posts/\(id)/approve", body: EmptyPayload())
            await refreshDashboard()
        }
    }

    func reject(post: PendingPost, reason: String) async {
        await rejectPost(id: post.id, reason: reason)
    }

    func reject(post: AdminPostDetail, reason: String) async {
        await rejectPost(id: post.id, reason: reason)
    }

    func rejectPost(id: String, reason: String) async {
        await run {
            let _: EmptyResponse = try await client.post("/api/admin/posts/\(id)/reject", body: RejectPostBody(reason: reason))
            await refreshDashboard()
        }
    }

    func resolve(report: SafetyReport, decision: String, reason: String? = nil) async {
        await run {
            let _: ReportMutationResponse = try await client.post("/api/admin/reports/\(report.id)/resolve", body: ResolveReportBody(decision: decision, reason: reason))
            await refreshDashboard()
        }
    }

    func loadUsers() async {
        guard role.canManageAccess else { return }
        await run {
            let response: AdminUsersResponse = try await client.get("/api/admin/users")
            users = response.users
        }
    }

    func updateStatus(for user: AdminUser, status: AccountStatus) async {
        await run {
            let _: EmptyResponse = try await client.patch("/api/admin/users/\(user.id)/status", body: UserStatusBody(status: status.rawValue))
            await loadUsers()
        }
    }

    func updateRole(for user: AdminUser, role: StaffRole) async {
        await run {
            let _: EmptyResponse = try await client.patch("/api/admin/users/\(user.id)/role", body: UserRoleBody(role: role.rawValue))
            await loadUsers()
        }
    }

    func createInviteCode(code: String, label: String, maxUses: Int) async {
        await run {
            let _: InviteCodeResponse = try await client.post("/api/admin/invite-codes", body: InviteCodeBody(code: code, label: label, maxUses: maxUses))
            await refreshDashboard()
        }
    }

    func registerPushDeviceToken(_ token: String) async {
        guard canUseAdminApp else { return }
        do {
            let _: EmptyResponse = try await client.post(
                "/api/push/devices",
                body: PushDeviceRegistrationBody(deviceToken: token)
            )
        } catch {
            alertMessage = "Push notifications could not be enabled: \(error.localizedDescription)"
        }
    }

    func recordPushRegistrationFailure(_ message: String) {
        alertMessage = "Push notifications could not be enabled: \(message)"
    }

    private func enablePushNotifications() async {
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.registerStoredTokenIfAvailable()
    }

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await operation()
        } catch APIClientError.unauthorized {
            signOut()
            alertMessage = "Please sign in again."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct EmptyPayload: Encodable {}
