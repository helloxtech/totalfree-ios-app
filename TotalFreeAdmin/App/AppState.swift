import Foundation
import AuthenticationServices
import SwiftUI
import UIKit

// =============================================================================
// AppState — single source of truth for session, profile/role, and shared data.
//
// The app is open to everyone: browsing works signed-out, any signed-in member
// can post / request / message, and staff (moderator/owner/admin) additionally
// see the moderation tools. Privileges are surfaced by role and ENFORCED by
// Supabase Row Level Security, never trusted from the client.
// =============================================================================

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var profile: Profile?
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var perms: Set<String> = []
    @Published private(set) var moderationCount = 0
    @Published private(set) var reportsCount = 0
    @Published private(set) var myPostsActionableCount = 0
    @Published private(set) var giftsGiven = 0
    @Published private(set) var entityKind = "Member"   // Member / Business / Organization
    @Published private(set) var badges: [AppBadge] = []

    /// Live conversation activity (a new request, a new chat message) belongs in the
    /// Messages tab. Request status outcomes (accepted/declined/completed) are alerts
    /// and stay in the Alerts feed. Mirrors the web app's `CONVERSATION_TYPES`.
    static let conversationTypes: Set<String> = ["request_new", "message_new"]
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var infoMessage: String?

    private let store: SessionStoring
    private let oauthPresentationContext = OAuthPresentationContextProvider()
    private var oauthSession: ASWebAuthenticationSession?

    init(sessionStore: SessionStoring = KeychainSessionStore()) {
        self.store = sessionStore
        PushNotificationService.shared.configure(appState: self)
    }

    // MARK: - Identity & privileges

    var isAuthed: Bool { session?.accessToken.isEmpty == false }
    var userId: String? { session?.user?.id }
    var role: UserRole { profile?.userRole ?? .user }
    var isStaff: Bool { role.isStaff }
    var isOwner: Bool { role.isOwner }
    var isVerified: Bool { session?.user?.isVerified ?? false }

    /// True if the person actually holds a permission (from my_perms()).
    func can(_ key: String) -> Bool { perms.contains(key) }
    /// Show the staff tab if the person holds any moderation/admin permission.
    var canSeeStaffArea: Bool { Perm.staffArea.contains { perms.contains($0) } }
    /// "Admin" for people who can manage users/roles; otherwise "Manage".
    var staffAreaTitle: String { (can(Perm.userManage) || can(Perm.roleManage)) ? "Admin" : "Manage" }

    /// Security-role label derived from EFFECTIVE PERMISSIONS (the source of truth;
    /// account type carries no authority). Shown on the Account screen.
    var securityRoleLabel: String {
        if can(Perm.roleManage) || can(Perm.userManage) { return "Admin" }
        if can(Perm.listingReview) || can(Perm.reportResolve) { return "Moderator" }
        return "Member"
    }
    var displayName: String { profile?.name ?? session?.user?.displayName ?? "Neighbour" }

    // MARK: - Session lifecycle

    func restoreSession() async {
        guard session == nil, let stored = store.load() else { return }
        session = stored
        await ensureFreshToken()
        await loadProfile()
        await afterAuth()
    }

    func signIn(email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let s = try await SupabaseClient().signIn(email: email, password: password)
            await applySession(s)
        } catch {
            alertMessage = message(for: error)
        }
    }

    func signUp(name: String, email: String, password: String) async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await SupabaseClient().signUp(email: email, password: password, name: name) {
            case .session(let s):
                await applySession(s)
            case .needsEmailVerification:
                infoMessage = "Almost there — check your email to confirm your account, then sign in."
            }
        } catch {
            alertMessage = message(for: error)
        }
    }

    func signInWithOAuth(_ provider: OAuthProvider) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let authURL = try SupabaseClient().mobileOAuthStartURL(provider: provider)
            let callbackURL = try await openOAuthSession(url: authURL)
            let s = try await SupabaseClient().session(fromOAuthCallback: callbackURL)
            await applySession(s)
        } catch OAuthSignInError.cancelled {
            // User cancelled the web auth sheet; no app-level alert needed.
        } catch {
            alertMessage = message(for: error)
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard SupabaseConfig.isMobileAuthRedirect(url) else { return }
        do {
            let s = try await SupabaseClient().session(fromOAuthCallback: url)
            await applySession(s)
        } catch {
            alertMessage = message(for: error)
        }
    }

    func signOut() {
        let token = PushNotificationService.shared.currentDeviceToken
        if let uid = userId, let token {
            let c = SupabaseClient(accessToken: session?.accessToken)
            Task { try? await c.deleteDeviceToken(userId: uid, token: token) }
        }
        let signOutClient = SupabaseClient(accessToken: session?.accessToken)
        Task { await signOutClient.signOutRemote() }
        store.clear()
        session = nil
        profile = nil
        notifications = []
        unreadCount = 0
        perms = []
        moderationCount = 0
        reportsCount = 0
        myPostsActionableCount = 0
        giftsGiven = 0
        entityKind = "Member"
        badges = []
    }

    private func applySession(_ s: AuthSession) async {
        session = s
        try? store.save(s)
        await loadProfile()
        await afterAuth()
    }

    private func afterAuth() async {
        await loadPerms()
        await refreshNotifications()
        await refreshStaffCounts()
        await refreshMyPostsCount()
        await refreshGifts()
        await refreshEntityKind()
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await PushNotificationService.shared.registerStoredTokenIfAvailable()
    }

    func loadProfile() async {
        guard let uid = userId else { profile = nil; return }
        profile = try? await client().fetchProfile(userId: uid)
    }

    func loadPerms() async {
        guard isAuthed else { perms = []; return }
        if let keys = try? await client().fetchMyPerms() { perms = Set(keys) }
    }

    /// Total count shown on the staff tab badge.
    var staffBadgeCount: Int { moderationCount + reportsCount }

    func refreshStaffCounts() async {
        guard isAuthed else { moderationCount = 0; reportsCount = 0; return }
        moderationCount = can(Perm.listingReview) ? ((try? await client().countPendingListings()) ?? moderationCount) : 0
        reportsCount = can(Perm.reportResolve) ? ((try? await client().countOpenReports()) ?? reportsCount) : 0
    }

    /// Count of the member's own posts needing attention — drives the My Posts tab badge.
    func refreshMyPostsCount() async {
        guard let uid = userId else { myPostsActionableCount = 0; return }
        myPostsActionableCount = (try? await client().countMyActionableListings(ownerId: uid)) ?? myPostsActionableCount
    }

    /// Completed gifts → the person's contributor level (shown on Account).
    func refreshGifts() async {
        guard let uid = userId else { giftsGiven = 0; return }
        giftsGiven = (try? await client().countMyGifts(ownerId: uid)) ?? giftsGiven
    }

    /// The person's entity kind (Member/Business/Organization) — picks the badge track.
    func refreshEntityKind() async {
        guard isAuthed else { entityKind = "Member"; return }
        if let k = try? await client().fetchMyEntityKind(), !k.isEmpty { entityKind = k }
    }

    /// Earned achievement badges (shown on Account).
    func refreshBadges() async {
        guard isAuthed else { badges = []; return }
        if let b = try? await client().fetchMyBadges() { badges = b }
    }

    // MARK: - Notifications

    /// Alerts shown in the bell feed — everything that isn't a conversation event.
    /// Conversation events live in the Messages tab instead.
    var alertNotifications: [AppNotification] {
        notifications.filter { !Self.conversationTypes.contains($0.type) }
    }

    func refreshNotifications() async {
        guard let uid = userId else { return }
        if let list = try? await client().fetchNotifications(userId: uid) {
            notifications = list
            unreadCount = list.filter { !$0.read && !Self.conversationTypes.contains($0.type) }.count
        }
    }

    func markNotificationRead(_ id: String) async {
        await perform { try await $0.markNotificationRead(id: id) }
        await refreshNotifications()
    }

    func deleteNotification(_ id: String) async {
        notifications.removeAll { $0.id == id }
        unreadCount = notifications.filter { !$0.read && !Self.conversationTypes.contains($0.type) }.count
        await perform { try await $0.deleteNotification(id: id) }
    }

    /// Mark every unread *alert* (non-conversation) notification read, leaving
    /// conversation unreads — and the Messages badge — untouched.
    func markAllAlertsRead() async {
        let ids = alertNotifications.filter { !$0.read }.map { $0.id }
        guard !ids.isEmpty else { return }
        for id in ids { _ = await perform { try await $0.markNotificationRead(id: id) } }
        await refreshNotifications()
    }

    /// Unread alerts that relate to conversations — drives the Messages tab badge.
    var messagesUnreadCount: Int {
        notifications.filter { !$0.read && Self.conversationTypes.contains($0.type) }.count
    }

    /// Whether a specific conversation (request thread) has unread activity.
    func conversationHasUnread(_ requestId: String?) -> Bool {
        guard let requestId else { return false }
        return notifications.contains {
            !$0.read && $0.targetRequestId == requestId && Self.conversationTypes.contains($0.type)
        }
    }

    /// Clear conversation alerts for one request when its thread is opened.
    func markNotificationsForRequest(_ requestId: String) async {
        let ids = notifications.filter { !$0.read && $0.targetRequestId == requestId }.map { $0.id }
        guard !ids.isEmpty else { return }
        for id in ids { _ = await perform { try await $0.markNotificationRead(id: id) } }
        await refreshNotifications()
    }

    // MARK: - Push registration callbacks

    func registerPushDeviceToken(_ token: String) async {
        guard let uid = userId else { return }
        try? await client().registerDeviceToken(
            userId: uid,
            token: token,
            apnsEnvironment: PushNotificationService.shared.apnsEnvironment,
            bundleId: PushNotificationService.shared.bundleId
        )
    }

    func recordPushRegistrationFailure(_ message: String) {
        // Non-fatal: the in-app notification feed still works without APNs.
        #if DEBUG
        print("[Push] registration failed: \(message)")
        #endif
    }

    // MARK: - Networking helpers (token refresh + uniform error handling)

    /// Returns a client carrying a fresh access token (refreshing if near expiry).
    func client() async -> SupabaseClient {
        await ensureFreshToken()
        return SupabaseClient(accessToken: session?.accessToken)
    }

    /// Run a read, surfacing errors centrally. Returns nil on failure.
    func load<T>(_ op: (SupabaseClient) async throws -> T) async -> T? {
        do {
            return try await op(client())
        } catch let error {
            await handle(error)
            return nil
        }
    }

    /// Run a mutation, surfacing errors centrally. Returns true on success.
    @discardableResult
    func perform(_ op: (SupabaseClient) async throws -> Void) async -> Bool {
        do {
            try await op(client())
            return true
        } catch let error {
            await handle(error)
            return false
        }
    }

    private func handle(_ error: Error) async {
        if case SupabaseError.unauthorized = error {
            alertMessage = "Your session expired. Please sign in again."
            signOut()
        } else {
            alertMessage = message(for: error)
        }
    }

    private func ensureFreshToken() async {
        guard let s = session, let exp = s.expiresAt else { return }
        if Date().timeIntervalSince1970 < exp - 60 { return }
        do {
            let refreshed = try await SupabaseClient().refresh(refreshToken: s.refreshToken)
            session = refreshed
            try? store.save(refreshed)
        } catch {
            store.clear()
            session = nil
            profile = nil
        }
    }

    private func message(for error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if text.localizedCaseInsensitiveContains("email rate limit exceeded")
            || text.localizedCaseInsensitiveContains("rate limit") {
            return "Too many confirmation emails were sent. Please wait a bit and try again."
        }
        if text.localizedCaseInsensitiveContains("Unexpected status code returned from hook") {
            return "We couldn't send the confirmation email. Please try again in a moment."
        }
        return text
    }

    private func openOAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SupabaseConfig.mobileAuthCallbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in self?.oauthSession = nil }
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: OAuthSignInError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: SupabaseError.noResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = oauthPresentationContext
            session.prefersEphemeralWebBrowserSession = false
            oauthSession = session
            if !session.start() {
                oauthSession = nil
                continuation.resume(throwing: SupabaseError.noResponse)
            }
        }
    }
}

private enum OAuthSignInError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        }
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
