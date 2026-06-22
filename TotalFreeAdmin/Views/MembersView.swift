import SwiftUI

/// People & roles. Visible with user.view; role changes require role.manage
/// (`set_user_role` is also enforced server-side). Pushed inside the staff hub.
struct UsersView: View {
    @EnvironmentObject private var appState: AppState
    let canManageRoles: Bool

    @State private var users: [AdminUserRow] = []
    @State private var loading = false
    @State private var query = ""

    private var filtered: [AdminUserRow] {
        guard !query.isEmpty else { return users }
        let q = query.lowercased()
        return users.filter {
            ($0.name?.lowercased().contains(q) ?? false) || ($0.email?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        Group {
            if loading && users.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { user in
                    NavigationLink {
                        UserDetailView(user: user, canManage: canManageRoles) { Task { await reload() } }
                    } label: {
                        UserRowSummary(user: user)
                    }
                }
            }
        }
        .navigationTitle("People & roles")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search name or email")
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.adminListUsers() }) { users = r }
    }
}

private struct UserRowSummary: View {
    let user: AdminUserRow
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 40, height: 40)
                Text(initials(user.displayName)).font(.caption.bold()).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let email = user.email { Text(email).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            RoleBadge(role: user.userRole)
        }
        .padding(.vertical, 2)
    }
}

struct RoleBadge: View {
    let role: UserRole
    var body: some View {
        Text(role.label)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(colorForRole(role).opacity(0.15), in: Capsule())
            .foregroundStyle(colorForRole(role))
    }
}

/// User detail: the person's account type, the security roles and teams assigned
/// to them (each clickable + editable), plus their posts. Mirrors the web model —
/// account type is just the entity kind; staff access comes from roles + teams.
struct UserDetailView: View {
    @EnvironmentObject private var appState: AppState
    let user: AdminUserRow
    let canManage: Bool
    var onChanged: () -> Void

    @State private var currentRole: UserRole
    @State private var roles: [SecurityRole] = []
    @State private var userRoles: [UserRoleLink] = []
    @State private var teams: [TeamRow] = []
    @State private var teamMembers: [TeamMemberLink] = []
    @State private var teamRoles: [TeamRoleLink] = []
    @State private var posts: [Listing] = []
    @State private var working = false

    init(user: AdminUserRow, canManage: Bool, onChanged: @escaping () -> Void = {}) {
        self.user = user
        self.canManage = canManage
        self.onChanged = onChanged
        _currentRole = State(initialValue: user.userRole)
    }

    private let entityKinds: [(value: String, label: String)] = [
        ("user", "Neighbour"), ("partner", "Organization"), ("sponsor", "Business"),
    ]

    private var assignedRoleIds: Set<String> { Set(userRoles.filter { $0.userId == user.id }.map(\.roleId)) }
    private var assignedRoles: [SecurityRole] { roles.filter { assignedRoleIds.contains($0.id) } }
    private var unassignedRoles: [SecurityRole] { roles.filter { !assignedRoleIds.contains($0.id) } }
    private var memberTeamIds: Set<String> { Set(teamMembers.filter { $0.userId == user.id }.map(\.teamId)) }
    private var memberTeams: [TeamRow] { teams.filter { memberTeamIds.contains($0.id) } }
    private var nonMemberTeams: [TeamRow] { teams.filter { !memberTeamIds.contains($0.id) } }
    private var effectiveRoleNames: [String] {
        var ids = assignedRoleIds
        for t in memberTeams where t.inheritRoles != false {
            for tr in teamRoles where tr.teamId == t.id { ids.insert(tr.roleId) }
        }
        return roles.filter { ids.contains($0.id) }.map(\.name).sorted()
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15)).frame(width: 56, height: 56)
                        Text(initials(user.displayName)).font(.title3.bold()).foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName).font(.headline)
                        if let email = user.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                        RoleBadge(role: currentRole)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                if let created = user.createdAt { LabeledContent("Joined", value: relativeDate(created)) }
                LabeledContent("Effective roles", value: effectiveRoleNames.isEmpty ? "Member" : effectiveRoleNames.joined(separator: ", "))
            }

            if canManage {
                Section {
                    Picker("Account type", selection: accountTypeBinding) {
                        ForEach(entityKinds, id: \.value) { kind in Text(kind.label).tag(kind.value) }
                    }
                } header: {
                    Text("Account type")
                } footer: {
                    Text("Sets the kind of account and its starting team. It does not grant staff access on its own — that comes from the security roles and teams below.")
                }
            }

            Section {
                if assignedRoles.isEmpty {
                    Text("No security roles assigned.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(assignedRoles) { role in
                        NavigationLink { RoleDetailView(roleId: role.id, roleName: role.name) } label: {
                            Text(role.name).font(.subheadline)
                        }
                        .swipeActions {
                            if canManage {
                                Button(role: .destructive) { Task { await toggleRole(role.id, on: false) } } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
                if canManage, !unassignedRoles.isEmpty {
                    Menu {
                        ForEach(unassignedRoles) { role in Button(role.name) { Task { await toggleRole(role.id, on: true) } } }
                    } label: {
                        Label("Add role", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Security roles")
            } footer: {
                Text("Roles assigned to this person directly. Tap a role for details; swipe to remove.")
            }

            Section {
                if memberTeams.isEmpty {
                    Text("Not a member of any team.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(memberTeams) { team in
                        NavigationLink { TeamDetailView(teamId: team.id, teamName: team.name) } label: {
                            Text(team.name).font(.subheadline)
                        }
                        .swipeActions {
                            if canManage {
                                Button(role: .destructive) { Task { await toggleTeam(team.id, on: false) } } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                }
                if canManage, !nonMemberTeams.isEmpty {
                    Menu {
                        ForEach(nonMemberTeams) { team in Button(team.name) { Task { await toggleTeam(team.id, on: true) } } }
                    } label: {
                        Label("Add to team", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Teams")
            } footer: {
                Text("Teams grant their roles to members when inheritance is on.")
            }

            Section("Posts (\(posts.count))") {
                if posts.isEmpty {
                    Text("No posts").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(posts) { listing in
                        NavigationLink { ListingDetailView(listing: listing) } label: { ListingCard(listing: listing) }
                    }
                }
            }
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private var accountTypeBinding: Binding<String> {
        Binding {
            entityKinds.contains { $0.value == currentRole.rawValue } ? currentRole.rawValue : "user"
        } set: { newValue in
            Task { await changeAccountType(newValue) }
        }
    }

    private func reload() async {
        roles = await appState.load({ try await $0.fetchSecurityRoles() }) ?? []
        userRoles = await appState.load({ try await $0.fetchUserRoleLinks() }) ?? []
        teams = await appState.load({ try await $0.fetchTeams() }) ?? []
        teamMembers = await appState.load({ try await $0.fetchTeamMemberLinks() }) ?? []
        teamRoles = await appState.load({ try await $0.fetchTeamRoleLinks() }) ?? []
        posts = await appState.load({ try await $0.fetchMyListings(ownerId: user.id) }) ?? []
    }

    private func toggleRole(_ roleId: String, on: Bool) async {
        let ok = await appState.perform { try await $0.setUserRoleLink(userId: user.id, roleId: roleId, on: on) }
        if ok { appState.infoMessage = on ? "Role added." : "Role removed."; await reload(); onChanged() }
    }
    private func toggleTeam(_ teamId: String, on: Bool) async {
        let ok = await appState.perform { try await $0.setTeamMemberLink(teamId: teamId, userId: user.id, on: on) }
        if ok { appState.infoMessage = on ? "Added to team." : "Removed from team."; await reload(); onChanged() }
    }
    private func changeAccountType(_ value: String) async {
        guard value != currentRole.rawValue, !working else { return }
        working = true
        let ok = await appState.perform { try await $0.setUserRole(target: user.id, role: value) }
        working = false
        if ok {
            currentRole = UserRole(rawValue: value) ?? .user
            appState.infoMessage = "Account type updated."
            await reload()
            onChanged()
        }
    }
}

private func initials(_ name: String) -> String {
    String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased()
}

private func colorForRole(_ role: UserRole) -> Color {
    switch role {
    case .admin, .owner: .red
    case .moderator: .orange
    case .sponsor: .blue
    case .partner: .purple
    case .user: .gray
    }
}
