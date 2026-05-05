import SwiftUI

struct MembersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""

    var filteredUsers: [AdminUser] {
        guard !query.isEmpty else { return appState.users }
        return appState.users.filter {
            $0.email.localizedCaseInsensitiveContains(query)
            || $0.displayName.localizedCaseInsensitiveContains(query)
            || $0.postalCode.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredUsers.isEmpty {
                    EmptyStateRow(
                        title: "No members match this search",
                        message: "Try a name, email, or postal code.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                } else {
                    ForEach(filteredUsers) { user in
                        NavigationLink {
                            MemberDetailView(user: user)
                        } label: {
                            MemberRow(user: user)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search members")
            .navigationTitle("Members")
            .task {
                if appState.users.isEmpty {
                    await appState.loadUsers()
                }
            }
            .refreshable { await appState.loadUsers() }
        }
    }
}

struct MemberRow: View {
    let user: AdminUser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(user.displayName.isEmpty ? user.email : user.displayName)
                .font(.headline)
            Text(user.email)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(user.role.label)
                Text(user.status.label)
                if !user.postalCode.isEmpty { Text(user.postalCode) }
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct MemberDetailView: View {
    @EnvironmentObject private var appState: AppState
    let user: AdminUser
    @State private var selectedStatus: AccountStatus
    @State private var selectedRole: StaffRole

    init(user: AdminUser) {
        self.user = user
        _selectedStatus = State(initialValue: user.status)
        _selectedRole = State(initialValue: user.role)
    }

    var body: some View {
        Form {
            Section("Member") {
                LabeledContent("Name", value: user.displayName.isEmpty ? "No display name" : user.displayName)
                LabeledContent("Email", value: user.email)
                LabeledContent("Postal code", value: user.postalCode.isEmpty ? "Unknown" : user.postalCode)
                LabeledContent("Community", value: user.community?.name ?? "Unknown")
            }

            Section("Activity") {
                LabeledContent("Posts", value: "\(user.stats.totalPosts)")
                LabeledContent("Responses sent", value: "\(user.stats.responsesSent)")
                LabeledContent("Reports filed", value: "\(user.stats.reportsFiled)")
            }

            if appState.role.canManageAccess && !user.isSelf {
                Section("Account status") {
                    Picker("Status", selection: $selectedStatus) {
                        ForEach([AccountStatus.active, .suspended, .banned], id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    Button("Save status") {
                        Task { await appState.updateStatus(for: user, status: selectedStatus) }
                    }
                }
            }

            if appState.role.canManageRoles && !user.isSelf {
                Section("Role") {
                    Picker("Role", selection: $selectedRole) {
                        ForEach([StaffRole.member, .moderator, .admin, .superAdmin], id: \.self) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    Button("Save role") {
                        Task { await appState.updateRole(for: user, role: selectedRole) }
                    }
                }
            }
        }
        .navigationTitle("Member")
    }
}
