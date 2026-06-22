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
                .tabItem { Label(appState.t("tab.browse"), systemImage: "square.grid.2x2") }

            if appState.isAuthed {
                MyStuffView()
                    .tabItem { Label(appState.t("tab.myPosts"), systemImage: "shippingbox") }
                    .badge(appState.myPostsActionableCount)

                MessagesView()
                    .tabItem { Label(appState.t("tab.messages"), systemImage: "bubble.left.and.bubble.right") }
                    .badge(appState.messagesUnreadCount)
            }

            if appState.canSeeStaffArea {
                StaffHubView()
                    .tabItem { Label(appState.staffAreaTitle, systemImage: "checkmark.shield") }
                    .badge(appState.staffBadgeCount)
            }

            AccountView()
                .tabItem { Label(appState.t("tab.account"), systemImage: "person.crop.circle") }
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
                        hubLink("No image", "photo.on.rectangle.angled", .mint, badge: appState.missingImagesCount) { NoImageListingsView() }
                    }
                    if appState.can(Perm.reportResolve) {
                        hubLink("Reports", "flag", .red, badge: appState.reportsCount) { ReportsView() }
                    }
                    if appState.can(Perm.claimResolve) {
                        hubLink("Organization claims", "checkmark.seal", .blue, badge: appState.claimsCount) { ClaimsView() }
                    }
                    if appState.can(Perm.businessApprove) {
                        hubLink("Business approvals", "building.2", .indigo, badge: appState.businessApprovalsCount) { SponsorsView() }
                    }
                }

                if appState.can(Perm.messageReadAny) || appState.can(Perm.analyticsView) {
                    Section("Oversight") {
                        if appState.can(Perm.messageReadAny) {
                            hubLink("Message oversight", "bubble.left.and.bubble.right", .teal) { ConversationsView() }
                        }
                        if appState.can(Perm.analyticsView) {
                            hubLink("Analytics", "chart.bar", .green) { AnalyticsView() }
                        }
                    }
                }

                if appState.can(Perm.userView) || appState.can(Perm.teamManage) || appState.can(Perm.roleManage) {
                    Section("Access") {
                        if appState.can(Perm.userView) {
                            hubLink("User directory", "person.2", .gray) {
                                UsersView(canManageRoles: appState.can(Perm.roleManage))
                            }
                        }
                        if appState.can(Perm.userManage) || appState.can(Perm.roleManage) {
                            hubLink("Duty", "calendar.badge.clock", .green) { ModeratorDutyView() }
                        }
                        if appState.can(Perm.teamManage) || appState.can(Perm.userView) {
                            hubLink("Teams", "person.3", .cyan) { TeamsView() }
                        }
                        if appState.can(Perm.roleManage) {
                            hubLink("Roles", "shield.lefthalf.filled", .indigo) { RolesView() }
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

struct NoImageListingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var listings: [Listing] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && listings.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if listings.isEmpty {
                EmptyState(
                    title: "No missing images",
                    message: "Active listings all have a visible image or placeholder.",
                    systemImage: "photo.on.rectangle.angled"
                )
            } else {
                List(listings) { listing in
                    NavigationLink { ListingDetailView(listing: listing) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(listing.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("\(listing.categoryLabel) · \(listing.locationText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let created = listing.createdAt {
                                    Text(relativeDate(created)).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("No image")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let rows = await appState.load({ try await $0.fetchListingsMissingImages() }) {
            listings = rows
            await appState.refreshStaffCounts()
        }
    }
}

struct ModeratorDutyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var candidates: [ModeratorDutyPerson] = []
    @State private var duty: [ModeratorDutyShift] = []
    @State private var selectedIds = Set<String>()
    @State private var selectedDate = Date()
    @State private var repeatMode = DutyRepeatMode.dateOnly
    @State private var weeks = 4
    @State private var loading = false
    @State private var saving = false

    var body: some View {
        List {
            Section {
                DatePicker("Duty date", selection: $selectedDate, displayedComponents: .date)
                Picker("Apply to", selection: $repeatMode) {
                    ForEach(DutyRepeatMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Stepper("For \(weeks) week\(weeks == 1 ? "" : "s")", value: $weeks, in: 1...12)
                    .disabled(repeatMode == .dateOnly)
            } footer: {
                Text("Admins always receive moderation alerts. Duty moderators also receive review, report, claim, and business approval alerts for their assigned days.")
            }

            Section("Moderators") {
                if loading && candidates.isEmpty {
                    ProgressView()
                } else if candidates.isEmpty {
                    Text("No schedulable moderators. Give a user moderation permissions first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { person in
                        Toggle(isOn: binding(for: person.userId)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).font(.subheadline.weight(.semibold))
                                Text([person.email, person.displayRole].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() }
                        else { Label("Save duty", systemImage: "checkmark.circle") }
                        Spacer()
                    }
                }
                .disabled(saving || loading)
            }

            Section("Upcoming") {
                if groupedDuty.isEmpty {
                    Text("No duty shifts scheduled in the next two weeks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedDuty.keys.sorted(), id: \.self) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayDay(day)).font(.subheadline.weight(.semibold))
                            Text(groupedDuty[day]?.map(\.name).joined(separator: ", ") ?? "No one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Duty")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: selectedDate) { _, _ in syncSelectionForSelectedDate() }
    }

    private var groupedDuty: [String: [ModeratorDutyShift]] {
        Dictionary(grouping: duty, by: \.dutyDate)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding {
            selectedIds.contains(id)
        } set: { isOn in
            if isOn { selectedIds.insert(id) }
            else { selectedIds.remove(id) }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        candidates = await appState.load({ try await $0.adminListModeratorDutyCandidates() }) ?? []
        duty = await appState.load({ try await $0.adminListModeratorDuty(days: 21) }) ?? []
        syncSelectionForSelectedDate()
    }

    private func save() async {
        let dates = selectedDates()
        guard !dates.isEmpty else { return }
        saving = true
        let ids = Array(selectedIds)
        let ok = await appState.perform { client in
            _ = try await client.adminSetModeratorDutyBulk(dates: dates, userIds: ids)
        }
        saving = false
        if ok {
            appState.infoMessage = ids.isEmpty ? "Duty cleared." : "Duty saved."
            await reload()
        }
    }

    private func syncSelectionForSelectedDate() {
        selectedIds = Set(groupedDuty[dateKey(selectedDate)]?.map(\.userId) ?? [])
    }

    private func selectedDates() -> [String] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        if repeatMode == .dateOnly { return [dateKey(start)] }
        let totalDays = max(1, weeks) * 7
        return (0..<totalDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return repeatMode.includes(date, calendar: calendar, anchor: start) ? dateKey(date) : nil
        }
    }
}

private enum DutyRepeatMode: String, CaseIterable, Identifiable {
    case dateOnly, thisWeekday, everyDay, weekdays, weekends
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dateOnly: "Just this date"
        case .thisWeekday: "This weekday"
        case .everyDay: "Every day"
        case .weekdays: "Weekdays"
        case .weekends: "Weekends"
        }
    }

    func includes(_ date: Date, calendar: Calendar, anchor: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch self {
        case .dateOnly:
            return calendar.isDate(date, inSameDayAs: anchor)
        case .thisWeekday:
            return weekday == calendar.component(.weekday, from: anchor)
        case .everyDay:
            return true
        case .weekdays:
            return (2...6).contains(weekday)
        case .weekends:
            return weekday == 1 || weekday == 7
        }
    }
}

struct TeamsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var users: [AdminUserRow] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && users.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    teamSection("Moderation team", users.filter { $0.userRole.isStaff })
                    teamSection("Organizations", users.filter { $0.userRole == .partner })
                    teamSection("Businesses", users.filter { $0.userRole == .sponsor })
                }
            }
        }
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func teamSection(_ title: String, _ rows: [AdminUserRow]) -> some View {
        Section(title) {
            if rows.isEmpty {
                Text("No members yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName).font(.subheadline.weight(.semibold))
                            if let email = user.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        RoleBadge(role: user.userRole)
                    }
                }
            }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let rows = await appState.load({ try await $0.adminListUsers() }) { users = rows }
    }
}

struct RolesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Role guide") {
                roleGuide(.user, "Can browse, request, post, message, and manage their own posts.")
                roleGuide(.partner, "Organization account for public programs and community resources.")
                roleGuide(.sponsor, "Business account for free local offers and approvals.")
                roleGuide(.moderator, "Can review posts, reports, claims, and scanner finds when permitted.")
                roleGuide(.owner, "Can manage moderation operations, duty, users, and roles.")
                roleGuide(.admin, "Full operational access.")
            }

            if appState.can(Perm.roleManage) {
                Section {
                    NavigationLink {
                        UsersView(canManageRoles: true)
                    } label: {
                        Label("Manage user roles", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
            }
        }
        .navigationTitle("Roles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleGuide(_ role: UserRole, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoleBadge(role: role)
            Text(description).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private func dateKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_CA_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func displayDay(_ key: String) -> String {
    let input = DateFormatter()
    input.calendar = Calendar(identifier: .gregorian)
    input.locale = Locale(identifier: "en_CA_POSIX")
    input.timeZone = .current
    input.dateFormat = "yyyy-MM-dd"
    guard let date = input.date(from: key) else { return key }
    let output = DateFormatter()
    output.dateStyle = .medium
    output.timeStyle = .none
    return output.string(from: date)
}
