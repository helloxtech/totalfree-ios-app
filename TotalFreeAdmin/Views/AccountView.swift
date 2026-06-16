import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAuth = false
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        NavigationStack {
            Group {
                if appState.isAuthed {
                    signedIn
                } else {
                    SignInPrompt(
                        title: "Welcome to TotalFree",
                        message: "Browse freely without an account. Sign in to post, request, and get alerts.",
                        systemImage: "person.crop.circle"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showAuth) { AuthView() }
        }
    }

    private var signedIn: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15)).frame(width: 56, height: 56)
                        Text(initials).font(.title3.bold()).foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.displayName).font(.headline)
                        Text(appState.session?.user?.email ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(appState.role.label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.accent)
                            if appState.isVerified {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label("Unverified", systemImage: "exclamationmark.triangle")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Profile") {
                Button {
                    nameDraft = appState.profile?.name ?? ""
                    editingName = true
                } label: {
                    Label("Edit display name", systemImage: "pencil")
                }
            }

            if !appState.isVerified {
                Section {
                    InfoCallout(
                        title: "Confirm your email",
                        message: "Check your inbox for the confirmation link to unlock posting and requests.",
                        systemImage: "envelope.badge"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Button(role: .destructive) {
                    appState.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("TotalFree — a warm place to find and share genuinely free things across Metro Vancouver.")
            }
        }
        .alert("Display name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let newName = nameDraft.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty, let uid = appState.userId else { return }
                Task {
                    let ok = await appState.perform { try await $0.updateProfileName(userId: uid, name: newName) }
                    if ok { await appState.loadProfile() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var initials: String {
        let parts = appState.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
