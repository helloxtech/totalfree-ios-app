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

                if appState.can(Perm.analyticsView) {
                    Section("Insights") {
                        // Message oversight removed — member messaging lives in the Messages tab.
                        hubLink("Analytics", "chart.bar", .green) { AnalyticsView() }
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

/// Weekly rota: pick who covers each weekday (repeats every week). Any single
/// day in the next two weeks can be overridden. Postgres dow is 0=Sun … 6=Sat;
/// Swift Calendar weekday is 1=Sun … 7=Sat, so dow = weekday - 1.
struct ModeratorDutyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var candidates: [ModeratorDutyPerson] = []
    @State private var rota: [DutyRotaEntry] = []
    @State private var overrides: [DutyOverrideRow] = []
    @State private var loading = false
    @State private var savingRota = false

    @State private var selectedDow = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var rotaSel = Set<String>()

    @State private var editing: DutyEditDate?
    @State private var overrideSel = Set<String>()
    @State private var savingOverride = false

    private let weekdays: [(dow: Int, label: String, short: String)] = [
        (1, "Monday", "Mon"), (2, "Tuesday", "Tue"), (3, "Wednesday", "Wed"),
        (4, "Thursday", "Thu"), (5, "Friday", "Fri"), (6, "Saturday", "Sat"), (0, "Sunday", "Sun"),
    ]

    var body: some View {
        List {
            Section {
                Picker("Weekday", selection: $selectedDow) {
                    ForEach(weekdays, id: \.dow) { wd in Text(wd.short).tag(wd.dow) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Weekly rota")
            } footer: {
                Text("Set who covers each weekday — it repeats every week. Admins always receive moderation alerts; on-duty moderators also get reports, claims, and post reviews for their day.")
            }

            Section("On duty every \(longLabel(selectedDow))") {
                if loading && candidates.isEmpty {
                    ProgressView()
                } else if candidates.isEmpty {
                    Text("No schedulable moderators. Give a user moderation permissions first.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { person in
                        Toggle(isOn: rotaBinding(for: person.userId)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.name).font(.subheadline.weight(.semibold))
                                Text([person.email, person.displayRole].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        Task { await saveRota() }
                    } label: {
                        HStack {
                            Spacer()
                            if savingRota { ProgressView() }
                            else { Label("Save \(longLabel(selectedDow)) rota", systemImage: "checkmark.circle") }
                            Spacer()
                        }
                    }
                    .disabled(savingRota)
                }
            }

            Section {
                ForEach(upcomingDays(), id: \.self) { day in
                    Button {
                        overrideSel = Set(effectivePeople(day).map(\.0))
                        editing = DutyEditDate(date: day)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(dayTitle(day)).font(.subheadline.weight(.semibold))
                                    if isOverridden(day) {
                                        Text("override").font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.18), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(effectiveNames(day)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Next 14 days")
            } footer: {
                Text("Each day follows the weekly rota unless you override it.")
            }
        }
        .navigationTitle("Duty")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .onChange(of: selectedDow) { _, _ in syncRotaSelection() }
        .sheet(item: $editing) { ctx in overrideSheet(ctx.date) }
    }

    // The per-date override editor (sheet). All logic stays in the parent so a
    // save can refresh the list immediately.
    private func overrideSheet(_ day: Date) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { person in
                        Toggle(isOn: overrideBinding(for: person.userId)) {
                            Text(person.name).font(.subheadline)
                        }
                    }
                } footer: {
                    Text("Choose who's on duty just for \(dayTitle(day)). Leave everyone off for nobody.")
                }
                Section {
                    Button {
                        Task { await saveOverride(day) }
                    } label: {
                        HStack {
                            Spacer()
                            if savingOverride { ProgressView() }
                            else { Label("Save this day", systemImage: "checkmark.circle") }
                            Spacer()
                        }
                    }
                    .disabled(savingOverride)
                    if isOverridden(day) {
                        Button(role: .destructive) {
                            Task { await resetOverride(day) }
                        } label: {
                            Label("Reset to weekly rota", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .navigationTitle(dayTitle(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { editing = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: helpers

    private func longLabel(_ dow: Int) -> String { weekdays.first { $0.dow == dow }?.label ?? "" }

    private func rotaBinding(for id: String) -> Binding<Bool> {
        Binding { rotaSel.contains(id) } set: { if $0 { rotaSel.insert(id) } else { rotaSel.remove(id) } }
    }
    private func overrideBinding(for id: String) -> Binding<Bool> {
        Binding { overrideSel.contains(id) } set: { if $0 { overrideSel.insert(id) } else { overrideSel.remove(id) } }
    }

    private func dowOf(_ date: Date) -> Int { Calendar.current.component(.weekday, from: date) - 1 }

    private func upcomingDays() -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func isOverridden(_ date: Date) -> Bool {
        let key = dateKey(date)
        return overrides.contains { $0.dutyDate == key }
    }

    /// (userId, name) effective on a date: the override if the day is overridden, else the weekly rota.
    private func effectivePeople(_ date: Date) -> [(String, String)] {
        if isOverridden(date) {
            let key = dateKey(date)
            return overrides.filter { $0.dutyDate == key && $0.userId != nil }
                .map { ($0.userId ?? "", $0.name ?? "Moderator") }
        }
        let dow = dowOf(date)
        return rota.filter { $0.weekday == dow }.map { ($0.userId, $0.name) }
    }

    private func effectiveNames(_ date: Date) -> String {
        let people = effectivePeople(date)
        return people.isEmpty ? "No one on duty" : people.map(\.1).joined(separator: ", ")
    }

    private func dayTitle(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "Today" : displayDay(dateKey(date))
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        candidates = await appState.load({ try await $0.adminListModeratorDutyCandidates() }) ?? []
        rota = await appState.load({ try await $0.adminListDutyRota() }) ?? []
        overrides = await appState.load({ try await $0.adminListDutyOverrides(days: 21) }) ?? []
        syncRotaSelection()
    }

    private func syncRotaSelection() {
        rotaSel = Set(rota.filter { $0.weekday == selectedDow }.map(\.userId))
    }

    private func saveRota() async {
        savingRota = true
        let dow = selectedDow
        let ids = Array(rotaSel)
        let ok = await appState.perform { client in
            _ = try await client.adminSetDutyRota(weekday: dow, userIds: ids)
        }
        savingRota = false
        if ok {
            appState.infoMessage = "\(longLabel(dow)) rota saved."
            await reload()
        }
    }

    private func saveOverride(_ day: Date) async {
        savingOverride = true
        let key = dateKey(day)
        let ids = Array(overrideSel)
        let ok = await appState.perform { try await $0.adminSetDutyOverride(date: key, userIds: ids) }
        savingOverride = false
        if ok {
            appState.infoMessage = "Override saved."
            editing = nil
            await reload()
        }
    }

    private func resetOverride(_ day: Date) async {
        let key = dateKey(day)
        let ok = await appState.perform { try await $0.adminClearDutyOverride(date: key) }
        if ok {
            appState.infoMessage = "Reverted to the weekly rota."
            editing = nil
            await reload()
        }
    }
}

private struct DutyEditDate: Identifiable {
    let date: Date
    var id: String { dateKey(date) }
}

struct TeamsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var teams: [TeamRow] = []
    @State private var teamRoles: [TeamRoleLink] = []
    @State private var teamMembers: [TeamMemberLink] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && teams.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if teams.isEmpty {
                EmptyState(title: "No teams", message: "Teams group people so they inherit roles together.", systemImage: "person.3")
            } else {
                List {
                    Section {
                        ForEach(teams) { team in
                            NavigationLink {
                                TeamDetailView(teamId: team.id, teamName: team.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.name).font(.subheadline.weight(.semibold))
                                    Text(teamSubtitle(team))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Tap a team to manage its roles and members. Members inherit the team's roles when inheritance is on.")
                    }
                }
            }
        }
        .navigationTitle("Teams")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func teamSubtitle(_ team: TeamRow) -> String {
        let m = teamMembers.filter { $0.teamId == team.id }.count
        let r = teamRoles.filter { $0.teamId == team.id }.count
        var s = "\(m) member\(m == 1 ? "" : "s") · \(r) role\(r == 1 ? "" : "s")"
        if team.inheritRoles == false { s += " · inheritance off" }
        return s
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        teams = await appState.load({ try await $0.fetchTeams() }) ?? []
        teamRoles = await appState.load({ try await $0.fetchTeamRoleLinks() }) ?? []
        teamMembers = await appState.load({ try await $0.fetchTeamMemberLinks() }) ?? []
    }
}

/// One team: its security roles (→ role detail) and members (→ user detail),
/// with swipe-to-remove and add-member when the viewer can manage teams.
struct TeamDetailView: View {
    @EnvironmentObject private var appState: AppState
    let teamId: String
    let teamName: String
    @State private var roles: [SecurityRole] = []
    @State private var teamRoles: [TeamRoleLink] = []
    @State private var teamMembers: [TeamMemberLink] = []
    @State private var users: [AdminUserRow] = []
    @State private var loading = false

    private var roleItems: [SecurityRole] {
        let ids = Set(teamRoles.filter { $0.teamId == teamId }.map(\.roleId))
        return roles.filter { ids.contains($0.id) }
    }
    private var memberItems: [AdminUserRow] {
        let ids = Set(teamMembers.filter { $0.teamId == teamId }.map(\.userId))
        return users.filter { ids.contains($0.id) }
    }
    private var nonMembers: [AdminUserRow] {
        let ids = Set(teamMembers.filter { $0.teamId == teamId }.map(\.userId))
        return users.filter { !ids.contains($0.id) }
    }

    var body: some View {
        List {
            Section("Security roles") {
                if roleItems.isEmpty {
                    Text("No roles assigned to this team.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(roleItems) { role in
                        NavigationLink { RoleDetailView(roleId: role.id, roleName: role.name) } label: {
                            Text(role.name).font(.subheadline)
                        }
                    }
                }
            }
            Section {
                if memberItems.isEmpty {
                    Text("No members yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(memberItems) { u in
                        NavigationLink { UserDetailView(user: u, canManage: appState.can(Perm.roleManage)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.displayName).font(.subheadline.weight(.semibold))
                                if let e = u.email { Text(e).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .swipeActions {
                            if appState.can(Perm.teamManage) {
                                Button(role: .destructive) { Task { await setMember(u.id, on: false) } } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                if appState.can(Perm.teamManage) { Text("Swipe a member to remove them from this team.") }
            }
            if appState.can(Perm.teamManage), !nonMembers.isEmpty {
                Section {
                    Menu {
                        ForEach(nonMembers) { u in
                            Button(u.displayName) { Task { await setMember(u.id, on: true) } }
                        }
                    } label: {
                        Label("Add member", systemImage: "person.badge.plus")
                    }
                }
            }
        }
        .navigationTitle(teamName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        roles = await appState.load({ try await $0.fetchSecurityRoles() }) ?? []
        teamRoles = await appState.load({ try await $0.fetchTeamRoleLinks() }) ?? []
        teamMembers = await appState.load({ try await $0.fetchTeamMemberLinks() }) ?? []
        users = await appState.load({ try await $0.adminListUsers() }) ?? []
    }

    private func setMember(_ uid: String, on: Bool) async {
        let ok = await appState.perform { try await $0.setTeamMemberLink(teamId: teamId, userId: uid, on: on) }
        if ok { appState.infoMessage = on ? "Member added." : "Member removed."; await reload() }
    }
}

struct RolesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var roles: [SecurityRole] = []
    @State private var rolePerms: [RolePermissionLink] = []
    @State private var userRoles: [UserRoleLink] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && roles.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roles.isEmpty {
                EmptyState(title: "No roles", message: "Security roles grant permissions to people and teams.", systemImage: "shield.lefthalf.filled")
            } else {
                List {
                    Section {
                        ForEach(roles) { role in
                            NavigationLink { RoleDetailView(roleId: role.id, roleName: role.name) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(role.name).font(.subheadline.weight(.semibold))
                                        if role.locked == true { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    Text(subtitle(role)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("Tap a role to see what it grants and who has it. A person's access is the union of every role assigned to them and their teams.")
                    }
                }
            }
        }
        .navigationTitle("Roles")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func subtitle(_ role: SecurityRole) -> String {
        let members = userRoles.filter { $0.roleId == role.id }.count
        let permText: String
        if role.locked == true {
            permText = "every permission"
        } else {
            let n = rolePerms.filter { $0.roleId == role.id }.count
            permText = "\(n) permission\(n == 1 ? "" : "s")"
        }
        return "\(permText) · \(members) direct member\(members == 1 ? "" : "s")"
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        roles = await appState.load({ try await $0.fetchSecurityRoles() }) ?? []
        rolePerms = await appState.load({ try await $0.fetchRolePermissionLinks() }) ?? []
        userRoles = await appState.load({ try await $0.fetchUserRoleLinks() }) ?? []
    }
}

/// One role: the permissions it grants, its direct members (→ user detail), and
/// the teams that confer it (→ team detail).
struct RoleDetailView: View {
    @EnvironmentObject private var appState: AppState
    let roleId: String
    let roleName: String
    @State private var perms: [Permission] = []
    @State private var rolePerms: [RolePermissionLink] = []
    @State private var userRoles: [UserRoleLink] = []
    @State private var users: [AdminUserRow] = []
    @State private var teams: [TeamRow] = []
    @State private var teamRoles: [TeamRoleLink] = []
    @State private var loading = false

    private var grantedPerms: [Permission] {
        let keys = Set(rolePerms.filter { $0.roleId == roleId }.map(\.permissionKey))
        return perms.filter { keys.contains($0.key) }
    }
    private var directMembers: [AdminUserRow] {
        let ids = Set(userRoles.filter { $0.roleId == roleId }.map(\.userId))
        return users.filter { ids.contains($0.id) }
    }
    private var grantingTeams: [TeamRow] {
        let ids = Set(teamRoles.filter { $0.roleId == roleId }.map(\.teamId))
        return teams.filter { ids.contains($0.id) }
    }

    var body: some View {
        List {
            Section("Permissions granted") {
                if grantedPerms.isEmpty {
                    Text("No permissions assigned to this role.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(grantedPerms) { p in Text(p.label ?? p.key).font(.subheadline) }
                }
            }
            Section("Members") {
                if directMembers.isEmpty {
                    Text("No one has this role directly.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(directMembers) { u in
                        NavigationLink { UserDetailView(user: u, canManage: appState.can(Perm.roleManage)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.displayName).font(.subheadline.weight(.semibold))
                                if let e = u.email { Text(e).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            if !grantingTeams.isEmpty {
                Section("Teams with this role") {
                    ForEach(grantingTeams) { t in
                        NavigationLink { TeamDetailView(teamId: t.id, teamName: t.name) } label: {
                            HStack {
                                Text(t.name).font(.subheadline)
                                if t.inheritRoles == false {
                                    Spacer(); Text("inheritance off").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(roleName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        perms = await appState.load({ try await $0.fetchPermissions() }) ?? []
        rolePerms = await appState.load({ try await $0.fetchRolePermissionLinks() }) ?? []
        userRoles = await appState.load({ try await $0.fetchUserRoleLinks() }) ?? []
        users = await appState.load({ try await $0.adminListUsers() }) ?? []
        teams = await appState.load({ try await $0.fetchTeams() }) ?? []
        teamRoles = await appState.load({ try await $0.fetchTeamRoleLinks() }) ?? []
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
