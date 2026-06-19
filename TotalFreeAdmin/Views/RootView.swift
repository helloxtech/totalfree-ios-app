import SwiftUI

/// Top-level tab container. Everyone gets Browse + Account. Signed-in members get
/// My Stuff (where they also post) + Alerts. Staff get a role-adaptive hub
/// (Manage for moderators, Admin for owners), with each section gated by the
/// person's real permissions (my_perms()).
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }

            if appState.isAuthed {
                MyStuffView()
                    .tabItem { Label("My Posts", systemImage: "shippingbox") }
                    .badge(appState.myPostsActionableCount)

                MessagesView()
                    .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                    .badge(appState.messagesUnreadCount)
            }

            if appState.canSeeStaffArea {
                StaffHubView()
                    .tabItem { Label(appState.staffAreaTitle, systemImage: "checkmark.shield") }
                    .badge(appState.staffBadgeCount)
            }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, appState.isAuthed {
                Task {
                    await appState.refreshNotifications()
                    await appState.refreshStaffCounts()
                    await appState.refreshMyPostsCount()
                }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { appState.alertMessage != nil },
                set: { if !$0 { appState.alertMessage = nil } }
            ),
            presenting: appState.alertMessage
        ) { _ in
            Button("OK", role: .cancel) { appState.alertMessage = nil }
        } message: { Text($0) }
        .overlay(alignment: .bottom) {
            if let msg = appState.infoMessage {
                ToastView(message: msg)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        appState.infoMessage = nil
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.infoMessage)
    }
}

/// Role-adaptive staff hub. Sections appear only if the person holds the matching
/// permission; the server enforces every action regardless.
struct StaffHubView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Review & moderation") {
                    if appState.can(Perm.listingReview) {
                        hubLink("Moderation queue", "rectangle.stack.badge.person.crop", .orange, badge: appState.moderationCount) { ModerationView() }
                        hubLink("Scanner finds", "sparkle.magnifyingglass", .purple) { CandidatesView() }
                    }
                    if appState.can(Perm.reportResolve) {
                        hubLink("Safety reports", "flag", .red, badge: appState.reportsCount) { ReportsView() }
                    }
                    if appState.can(Perm.claimResolve) {
                        hubLink("Organization claims", "checkmark.seal", .blue, badge: appState.claimsCount) { ClaimsView() }
                    }
                    if appState.can(Perm.businessApprove) {
                        hubLink("Business approvals", "building.2", .indigo, badge: appState.businessApprovalsCount) { SponsorsView() }
                    }
                }

                if appState.can(Perm.messageReadAny) || appState.can(Perm.analyticsView) || appState.can(Perm.userView) {
                    Section("Oversight") {
                        if appState.can(Perm.messageReadAny) {
                            hubLink("Message oversight", "bubble.left.and.bubble.right", .teal) { ConversationsView() }
                        }
                        if appState.can(Perm.analyticsView) {
                            hubLink("Analytics", "chart.bar", .green) { AnalyticsView() }
                        }
                        if appState.can(Perm.userView) {
                            hubLink("User directory", "person.2", .gray) {
                                UsersView(canManageRoles: appState.can(Perm.roleManage))
                            }
                        }
                    }
                }
            }
            .navigationTitle(appState.staffAreaTitle)
            .task { await appState.refreshStaffCounts() }
            .refreshable { await appState.loadPerms(); await appState.refreshStaffCounts() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await appState.loadPerms(); await appState.refreshStaffCounts() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .overlay {
                if appState.perms.isEmpty {
                    EmptyState(title: "No staff tools", message: "Your account doesn't have moderation permissions.", systemImage: "lock")
                }
            }
        }
    }

    private func hubLink<Destination: View>(
        _ title: String, _ icon: String, _ color: Color, badge: Int = 0,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
                Spacer()
                if badge > 0 {
                    // Prominent red count that visually matches the tab's badge,
                    // so it's obvious what the "1" on Admin refers to.
                    Text("\(badge)")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }
        }
    }
}
