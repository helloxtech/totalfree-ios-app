import SwiftUI
import PhotosUI
import UIKit

struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAuth = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false

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
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            avatarCircle
                            if uploadingAvatar {
                                ProgressView()
                                    .frame(width: 56, height: 56)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            Image(systemName: "camera.fill")
                                .font(.system(size: 11)).foregroundStyle(.white)
                                .padding(5).background(Theme.accent, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.displayName).font(.headline)
                        Text(appState.session?.user?.email ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(appState.securityRoleLabel)
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
                .onChange(of: avatarItem) { _, item in
                    guard let item else { return }
                    Task { await uploadAvatar(item) }
                }
            }

            Section("Your impact") {
                HStack(spacing: 14) {
                    Text(level.emoji).font(.system(size: 40))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.name).font(.headline)
                        Text("\(appState.giftsGiven) \(level.unit)\(appState.giftsGiven == 1 ? "" : "s") given")
                            .font(.caption).foregroundStyle(.secondary)
                        if let next = level.next {
                            ProgressView(value: Double(appState.giftsGiven - level.min), total: Double(max(1, next.min - level.min)))
                                .tint(Theme.accent)
                            Text("\(max(0, next.min - appState.giftsGiven)) more to \(next.name)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        } else {
                            Text("Top level — thank you! 💚").font(.caption2).foregroundStyle(Theme.accent)
                        }
                    }
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
        .task { await appState.refreshGifts(); await appState.refreshEntityKind() }
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let urlStr = appState.profile?.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else { initialsCircle }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.15)).frame(width: 56, height: 56)
            Text(initials).font(.title3.bold()).foregroundStyle(Theme.accent)
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let uid = appState.userId else { return }
        uploadingAvatar = true
        defer { uploadingAvatar = false; avatarItem = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
        let data = UIImage(data: raw)?.jpegResized(maxDimension: 512, quality: 0.85) ?? raw
        let ok = await appState.perform { client in
            let url = try await client.uploadAvatar(data, userId: uid)
            try await client.updateProfileAvatar(userId: uid, url: url)
        }
        if ok { await appState.loadProfile() }
    }

    private var level: ContributorLevel { ContributorLevel.forEntity(appState.entityKind, gifts: appState.giftsGiven) }

    private var initials: String {
        let parts = appState.displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
