import Charts
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.session == nil {
                LoginView()
            } else if appState.canUseAdminApp {
                AdminShellView()
            } else {
                AccessDeniedView()
            }
        }
        .overlay {
            if appState.isBusy {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(
            "Total Free Admin",
            isPresented: Binding(
                get: { appState.alertMessage != nil },
                set: { if !$0 { appState.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { appState.alertMessage = nil }
        } message: {
            Text(appState.alertMessage ?? "")
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center, spacing: 16) {
                        Image("TotalFreeLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Total Free Admin")
                                .font(.largeTitle.bold())
                            Text("Fast moderation for Semiahmoo student administrators.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await appState.signIn(email: email, password: password) }
                        } label: {
                            Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || password.isEmpty || appState.isBusy)
                    }

                    InfoCallout(
                        title: "Staff accounts only",
                        message: "Use an existing moderator, admin, or super-admin account. Member accounts cannot access this app.",
                        systemImage: "lock.shield"
                    )
                }
                .padding(24)
            }
            .navigationTitle("Sign in")
        }
    }
}

struct AccessDeniedView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Admin access required", systemImage: "lock.shield")
            } description: {
                Text("This app is only for active moderator, admin, and super-admin accounts.")
            } actions: {
                Button("Sign out") { appState.signOut() }
            }
            .navigationTitle("Access")
        }
    }
}

struct AdminShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: AdminTab = .queue

    var body: some View {
        TabView(selection: $selectedTab) {
            QueueView(selectedTab: $selectedTab)
                .tabItem { Label("Queue", systemImage: "tray.full") }
                .badge(appState.dashboard?.pendingPosts.count ?? 0)
                .tag(AdminTab.queue)

            ReportsView()
                .tabItem { Label("Reports", systemImage: "exclamationmark.shield") }
                .badge(appState.dashboard?.reports.count ?? 0)
                .tag(AdminTab.reports)

            if appState.role.canManageAccess {
                MembersView()
                    .tabItem { Label("Members", systemImage: "person.2") }
                    .tag(AdminTab.members)

                StatisticsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                    .tag(AdminTab.statistics)

                AccessView()
                    .tabItem { Label("Access", systemImage: "key") }
                    .tag(AdminTab.access)
            }
        }
        .task {
            if appState.dashboard == nil {
                await appState.refreshDashboard()
            }
        }
    }
}

enum AdminTab: Hashable {
    case queue
    case reports
    case members
    case statistics
    case access
}

struct StatisticsView: View {
    @EnvironmentObject private var appState: AppState

    private var postData: [ChartDatum] {
        guard let stats = appState.dashboard?.stats else { return [] }
        return [
            ChartDatum(label: "Draft", value: stats.draftPosts),
            ChartDatum(label: "Active", value: stats.activePosts),
            ChartDatum(label: "Pending", value: stats.pendingPosts),
            ChartDatum(label: "Reserved", value: stats.reservedPosts),
            ChartDatum(label: "Completed", value: stats.completedPosts),
            ChartDatum(label: "Closed", value: stats.closedPosts),
            ChartDatum(label: "Rejected", value: stats.rejectedPosts),
            ChartDatum(label: "Hidden", value: stats.hiddenPosts),
        ].filter { $0.value > 0 }
    }

    private var activityData: [ChartDatum] {
        guard let stats = appState.dashboard?.stats else { return [] }
        return [
            ChartDatum(label: "Views", value: stats.viewsToday),
            ChartDatum(label: "Visitors", value: stats.uniqueVisitorsToday),
            ChartDatum(label: "Signed in", value: stats.signedInVisitorsToday),
            ChartDatum(label: "Sign-ins", value: stats.signInsToday),
        ]
    }

    private var workloadData: [ChartDatum] {
        guard let stats = appState.dashboard?.stats else { return [] }
        return [
            ChartDatum(label: "Pending posts", value: stats.pendingPosts),
            ChartDatum(label: "Open reports", value: stats.openReports),
            ChartDatum(label: "Members", value: stats.members),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                if let stats = appState.dashboard?.stats {
                    Section {
                        LabeledContent("Views today", value: "\(stats.viewsToday)")
                        LabeledContent("Visitors today", value: "\(stats.uniqueVisitorsToday)")
                        LabeledContent("Signed-in visitors today", value: "\(stats.signedInVisitorsToday)")
                        LabeledContent("Sign-ins today", value: "\(stats.signInsToday)")
                        LabeledContent("Views in 7 days", value: "\(stats.views7d)")
                        LabeledContent("Visitors in 7 days", value: "\(stats.uniqueVisitors7d)")
                        LabeledContent("Signed-in visitors in 7 days", value: "\(stats.signedInVisitors7d)")
                        LabeledContent("Sign-ins in 7 days", value: "\(stats.signIns7d)")
                    } header: {
                        Text("Website activity")
                    } footer: {
                        Text("Counts are privacy-safe app events. No IP addresses or browser fingerprints are stored.")
                    }

                    Section {
                        LabeledContent("Total posts", value: "\(stats.totalPosts)")
                        LabeledContent("Active", value: "\(stats.activePosts)")
                        LabeledContent("Pending review", value: "\(stats.pendingPosts)")
                        LabeledContent("Reserved", value: "\(stats.reservedPosts)")
                        LabeledContent("Completed", value: "\(stats.completedPosts)")
                        LabeledContent("Hidden", value: "\(stats.hiddenPosts)")
                        LabeledContent("Rejected", value: "\(stats.rejectedPosts)")
                        LabeledContent("Closed", value: "\(stats.closedPosts)")
                        LabeledContent("Open reports", value: "\(stats.openReports)")
                        LabeledContent("Active members", value: "\(stats.members)")
                    } header: {
                        Text("Post counts")
                    } footer: {
                        Text("Reserved means a requester was accepted and pickup is being coordinated. Hidden means moderators removed the post from public browsing for safety or policy review.")
                    }

                    Section("Activity today") {
                        Chart(activityData) { item in
                            BarMark(
                                x: .value("Metric", item.label),
                                y: .value("Count", item.value)
                            )
                            .foregroundStyle(by: .value("Metric", item.label))
                        }
                        .frame(height: 220)
                    }

                    Section("Post status") {
                        Chart(postData) { item in
                            BarMark(
                                x: .value("Status", item.label),
                                y: .value("Count", item.value)
                            )
                            .foregroundStyle(by: .value("Status", item.label))
                        }
                        .frame(height: 220)
                    }

                    Section("Workload split") {
                        Chart(workloadData) { item in
                            SectorMark(
                                angle: .value("Count", item.value),
                                innerRadius: .ratio(0.55),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Type", item.label))
                        }
                        .frame(height: 220)
                    }

                    Section("7-day engagement") {
                        Chart([
                            ChartDatum(label: "Views", value: stats.views7d),
                            ChartDatum(label: "Visitors", value: stats.uniqueVisitors7d),
                            ChartDatum(label: "Signed in", value: stats.signedInVisitors7d),
                            ChartDatum(label: "Sign-ins", value: stats.signIns7d),
                        ]) { item in
                            SectorMark(
                                angle: .value("Count", item.value),
                                innerRadius: .ratio(0.55),
                                angularInset: 2
                            )
                            .foregroundStyle(by: .value("Metric", item.label))
                        }
                        .frame(height: 220)
                    }
                } else {
                    EmptyStateRow(
                        title: "No statistics loaded",
                        message: "Refresh the admin dashboard to load current counts.",
                        systemImage: "chart.bar"
                    )
                }
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshDashboard() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .refreshable { await appState.refreshDashboard() }
        }
    }
}

private struct ChartDatum: Identifiable {
    let id = UUID()
    let label: String
    let value: Int
}
