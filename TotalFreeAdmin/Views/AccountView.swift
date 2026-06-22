import SwiftUI
import PhotosUI
import UIKit

struct AccountView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("app.appearance") private var appearanceRaw = AppAppearance.bright.rawValue
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
                    signedOut
                }
            }
            .navigationTitle(appState.t("account.title"))
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
                                Label(appState.t("account.verified"), systemImage: "checkmark.seal.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label(appState.t("account.unverified"), systemImage: "exclamationmark.triangle")
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

                if !appState.badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(appState.badges) { b in
                                VStack(spacing: 3) {
                                    Text(b.emoji).font(.title3)
                                    Text(b.count.flatMap { $0 > 1 ? "\(b.label) ×\($0)" : nil } ?? b.label)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .frame(minWidth: 72)
                                .padding(.vertical, 6).padding(.horizontal, 6)
                                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }

            Section(appState.t("account.profile")) {
                Button {
                    nameDraft = appState.profile?.name ?? ""
                    editingName = true
                } label: {
                    Label(appState.t("account.editName"), systemImage: "pencil")
                }
            }

            Section("Alerts & notifications") {
                NavigationLink {
                    SavedAlertsView()
                } label: {
                    Label("Saved alerts", systemImage: "bell.badge")
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notification settings", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    NotificationsView()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }

            languageSection
            appearanceSection

            Section("App") {
                NavigationLink {
                    AppInfoView()
                } label: {
                    Label("Version & updates", systemImage: "arrow.down.app")
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
                    Label(appState.t("account.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Total Free — a warm place to find and share genuinely free things across Metro Vancouver.")
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
        .task { await appState.refreshGifts(); await appState.refreshEntityKind(); await appState.refreshBadges() }
    }

    private var signedOut: some View {
        List {
            Section {
                SignInPrompt(
                    title: appState.t("account.welcome"),
                    message: appState.t("account.welcomeBody"),
                    systemImage: "person.crop.circle"
                )
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            appearanceSection
        }
    }

    private var languageSection: some View {
        Section {
            Picker(appState.t("account.language"), selection: Binding(
                get: { appState.appLanguage.rawValue },
                set: { appState.setPreferredLocale($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text("\(language.nativeName) (\(language.label))").tag(language.rawValue)
                }
            }
        } header: {
            Text(appState.t("account.language"))
        } footer: {
            Text(appState.t("account.languageHint"))
        }
    }

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(appState.t("account.theme"), systemImage: "circle.lefthalf.filled")
                    .font(.subheadline.weight(.semibold))
                Picker(appState.t("account.theme"), selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.label, systemImage: option.systemImage)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
        } header: {
            Text(appState.t("account.appearance"))
        } footer: {
            Text("Bright is the default. Dark keeps the same Total Free layout with a low-light color scheme.")
        }
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

struct SavedAlertsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searches: [SavedSearch] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && searches.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searches.isEmpty {
                EmptyState(
                    title: "No saved alerts",
                    message: "Save a search from Browse to get notified when matching free finds are posted.",
                    systemImage: "bell.badge"
                )
            } else {
                List {
                    ForEach(searches) { search in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(search.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                Text(search.alertMode.capitalized)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Theme.accent)
                            }
                            if !search.details.isEmpty {
                                Text(search.details).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("All areas · all categories").font(.caption).foregroundStyle(.secondary)
                            }
                            if let created = search.createdAt {
                                Text("Saved \(relativeDate(created))").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await delete(search) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Saved alerts")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        if let rows = await appState.load({ try await $0.fetchSavedSearches(userId: uid) }) {
            searches = rows
        }
    }

    private func delete(_ search: SavedSearch) async {
        let ok = await appState.perform { try await $0.deleteSavedSearch(id: search.id) }
        if ok { searches.removeAll { $0.id == search.id } }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var prefs = NotificationPrefs.defaults()
    @State private var loading = false
    @State private var saving = false

    var body: some View {
        List {
            Section {
                Toggle("Push notifications", isOn: $prefs.pushEnabled)
                Toggle("Email notifications", isOn: $prefs.emailEnabled)
            } footer: {
                Text("Push requires iOS notification permission. Email can be turned off without changing your account.")
            }

            Section {
                Toggle("Saved search matches", isOn: $prefs.savedSearchAlerts)
                Toggle("Request updates", isOn: $prefs.requestUpdates)
                Toggle("Messages", isOn: $prefs.messageAlerts)
                Toggle("Weekly community digest", isOn: $prefs.communityDigest)
                Toggle("Local business free offers", isOn: $prefs.sponsorOffers)
            } header: {
                Text("What to send")
            } footer: {
                Text("Local business free offers are optional alerts from approved businesses offering something genuinely free.")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView() }
                        else { Text("Save notification settings").bold() }
                        Spacer()
                    }
                }
                .disabled(saving || loading)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial) }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        if let row = await appState.load({ try await $0.fetchNotificationPrefs(userId: uid) }) {
            prefs = row
        }
    }

    private func save() async {
        guard let uid = appState.userId else { return }
        saving = true
        let ok = await appState.perform { try await $0.updateNotificationPrefs(userId: uid, prefs: prefs) }
        saving = false
        if ok {
            appState.infoMessage = "Notification settings saved."
            await reload()
        }
    }
}

struct AppInfoView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                LabeledContent("App", value: "Total Free")
                LabeledContent("Version", value: versionText)
                LabeledContent("Backend", value: "totalfree.ca")
            }

            Section {
                Button {
                    checkForUpdates()
                } label: {
                    Label("Check for updates", systemImage: "arrow.down.app")
                }
                Link(destination: URL(string: "https://totalfree.ca")!) {
                    Label("Open TotalFree.ca", systemImage: "safari")
                }
            } footer: {
                Text("App Store and TestFlight builds update through Apple's update flow. This screen is ready for the store ID once the public listing is available.")
            }
        }
        .navigationTitle("Version & updates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func checkForUpdates() {
        if let storeId = Bundle.main.object(forInfoDictionaryKey: "TFAppStoreID") as? String,
           !storeId.trimmingCharacters(in: .whitespaces).isEmpty,
           let url = URL(string: "itms-apps://apps.apple.com/app/id\(storeId)") {
            UIApplication.shared.open(url)
        } else {
            appState.infoMessage = "This build updates through TestFlight or the App Store."
        }
    }
}
