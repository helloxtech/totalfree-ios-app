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

/// User detail with optional role management.
struct UserDetailView: View {
    @EnvironmentObject private var appState: AppState
    let user: AdminUserRow
    let canManage: Bool
    var onChanged: () -> Void

    @State private var currentRole: UserRole
    @State private var working = false
    @State private var posts: [Listing] = []

    init(user: AdminUserRow, canManage: Bool, onChanged: @escaping () -> Void) {
        self.user = user
        self.canManage = canManage
        self.onChanged = onChanged
        _currentRole = State(initialValue: user.userRole)
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
                if let created = user.createdAt {
                    LabeledContent("Joined", value: relativeDate(created))
                }
            }

            if canManage {
                Section("Change role") {
                    ForEach(UserRole.assignable) { role in
                        Button {
                            guard role != currentRole, !working else { return }
                            Task { await changeRole(role) }
                        } label: {
                            HStack {
                                Text(role.label).foregroundStyle(.primary)
                                Spacer()
                                if role == currentRole { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }
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
        .task {
            if let p = await appState.load({ try await $0.fetchMyListings(ownerId: user.id) }) { posts = p }
        }
    }

    private func changeRole(_ role: UserRole) async {
        working = true
        let ok = await appState.perform { try await $0.setUserRole(target: user.id, role: role.rawValue) }
        working = false
        if ok {
            currentRole = role
            appState.infoMessage = "Role updated to \(role.label)."
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
