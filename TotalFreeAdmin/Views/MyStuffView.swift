import SwiftUI

/// My posts — the listings I've shared. Posting also happens here (+ button).
struct MyStuffView: View {
    @EnvironmentObject private var appState: AppState
    @State private var listings: [Listing] = []
    @State private var loading = false
    @State private var showPost = false

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isAuthed {
                    SignInPrompt(
                        title: "Your posts live here",
                        message: "Sign in to share items and manage what you've posted.",
                        systemImage: "shippingbox"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loading && listings.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if listings.isEmpty {
                    EmptyState(title: "No posts yet", message: "Tap ＋ to give something away or post a wanted.", systemImage: "shippingbox")
                } else {
                    List {
                        if !offers.isEmpty {
                            Section("Giving away (\(offers.count))") {
                                ForEach(offers) { postRow($0) }
                            }
                        }
                        if !wanted.isEmpty {
                            Section("Wanted (\(wanted.count))") {
                                ForEach(wanted) { postRow($0) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("My Posts")
            .toolbar {
                if appState.isAuthed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPost = true } label: { Label("New post", systemImage: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showPost, onDismiss: { Task { await reload() } }) {
                PostView(asSheet: true)
            }
            .task { await reload() }
        }
    }

    private var offers: [Listing] { listings.filter { $0.listingKind != "wanted" } }
    private var wanted: [Listing] { listings.filter { $0.listingKind == "wanted" } }

    private func postRow(_ listing: Listing) -> some View {
        NavigationLink { ListingDetailView(listing: listing) } label: { ListingCard(listing: listing) }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchMyListings(ownerId: uid) }) { listings = r }
    }
}

/// Messages — every conversation I'm part of (requests I sent and received).
struct MessagesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var requests: [AppRequest] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isAuthed {
                    SignInPrompt(
                        title: "Your messages live here",
                        message: "Sign in to message neighbours about items.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loading && requests.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requests.isEmpty {
                    EmptyState(
                        title: "No messages yet",
                        message: "When you ask for an item or someone asks about your post, the conversation shows here.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                } else {
                    List(requestGroups) { group in
                        NavigationLink {
                            ListingRequestersView(group: group)
                        } label: {
                            RequestListingGroupRow(group: group, userId: appState.userId)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
            .navigationTitle("Messages")
            .task { await reload() }
        }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchMyRequests(userId: uid) }) { requests = r }
        await appState.refreshNotifications()
    }

    private var requestGroups: [RequestListingGroup] {
        Dictionary(grouping: requests, by: \.listingId)
            .map { listingId, rows in
                let sorted = rows.sorted { ($0.latestActivityAt ?? "") > ($1.latestActivityAt ?? "") }
                return RequestListingGroup(listingId: listingId, requests: sorted)
            }
            .sorted { ($0.latestActivityAt ?? "") > ($1.latestActivityAt ?? "") }
    }
}

private struct RequestListingGroup: Identifiable, Equatable {
    let listingId: String
    let requests: [AppRequest]

    var id: String { listingId }
    var title: String { requests.first?.itemTitle ?? "Listing" }
    var imageUrl: String? { requests.first?.listings?.imageUrl }
    var latestActivityAt: String? { requests.first?.latestActivityAt }
    var latestRequest: AppRequest? { requests.first }
}

private struct RequestListingGroupRow: View {
    let group: RequestListingGroup
    let userId: String?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(group.requests.count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                if let latest = group.latestRequest {
                    Text(counterpartyText(for: latest))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !latest.message.isEmpty {
                        Text(latest.message)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageUrl = group.imageUrl, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func counterpartyText(for request: AppRequest) -> String {
        if request.ownerId == userId {
            "Latest from \(request.requesterName) · \(relativeDate(request.latestActivityAt))"
        } else {
            "Latest to \(request.ownerName) · \(relativeDate(request.latestActivityAt))"
        }
    }
}

private struct ListingRequestersView: View {
    @EnvironmentObject private var appState: AppState
    let group: RequestListingGroup

    var body: some View {
        List(group.requests) { req in
            NavigationLink {
                RequestThreadView(request: req)
            } label: {
                RequestRow(request: req, isIncoming: req.ownerId == appState.userId, showsItemTitle: false)
            }
        }
        .listStyle(.plain)
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RequestRow: View {
    let request: AppRequest
    let isIncoming: Bool
    var showsItemTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(isIncoming ? "Received" : "Sent", systemImage: isIncoming ? "tray.and.arrow.down" : "paperplane")
                    .font(.caption2.bold())
                    .foregroundStyle(isIncoming ? Theme.accent : .blue)
                Spacer()
                StatusBadge(status: request.status)
            }
            Text(showsItemTitle ? request.itemTitle : counterpartyText)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if showsItemTitle {
                Text(counterpartyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !request.message.isEmpty {
                Text(request.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var counterpartyText: String {
        isIncoming ? "From \(request.requesterName)" : "To \(request.ownerName)"
    }
}

// MARK: - Conversation thread for a single request

struct RequestThreadView: View {
    @EnvironmentObject private var appState: AppState
    let request: AppRequest
    let readOnly: Bool

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var status: String
    @State private var loading = false
    @State private var confirmComplete = false

    init(request: AppRequest, readOnly: Bool = false) {
        self.request = request
        self.readOnly = readOnly
        _status = State(initialValue: request.status)
    }

    private var isIncoming: Bool { request.ownerId == appState.userId }

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ListingLoaderView(listingId: request.listingId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox").foregroundStyle(Theme.accent)
                    Text(request.itemTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text("View post").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
            Divider()

            if !readOnly && isIncoming && ["pending", "accepted", "declined", "completed"].contains(status) {
                manageBar
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text(request.message.isEmpty ? "Request started." : request.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                    ForEach(messages) { msg in
                        MessageBubble(message: msg, mine: msg.senderId == appState.userId)
                    }
                }
                .padding()
            }
            if readOnly {
                Label("Read-only — staff view", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(10).background(.bar)
            } else {
                composer
            }
        }
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { StatusBadge(status: status) }
        }
        .task {
            await loadMessages()
            if !readOnly { await appState.markNotificationsForRequest(request.id) }
        }
        .refreshable { await loadMessages() }
        .confirmationDialog("Mark this completed?", isPresented: $confirmComplete, titleVisibility: .visible) {
            Button("Mark completed") { Task { await setStatus("completed") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do this once the item has changed hands. You can reopen it later if needed.")
        }
    }

    /// Owner controls — decisions can be changed (Accepted ↔ Declined) any time.
    private var manageBar: some View {
        HStack(spacing: 10) {
            if status == "pending" || status == "declined" {
                Button { Task { await setStatus("accepted") } } label: {
                    Label(status == "declined" ? "Accept instead" : "Accept", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if status == "pending" || status == "accepted" {
                Button(role: .destructive) { Task { await setStatus("declined") } } label: {
                    Label(status == "accepted" ? "Change to decline" : "Decline", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if status == "accepted" {
                Button { confirmComplete = true } label: {
                    Label("Mark completed", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if status == "completed" {
                Button { Task { await setStatus("accepted") } } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(.bar)
    }

    private func loadMessages() async {
        loading = true
        defer { loading = false }
        if let m = await appState.load({ try await $0.fetchMessages(requestId: request.id) }) { messages = m }
    }

    private func send() async {
        guard let uid = appState.userId else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let ok = await appState.perform { try await $0.sendMessage(requestId: request.id, text: text, senderId: uid) }
        if ok { draft = ""; await loadMessages() }
    }

    private func setStatus(_ newStatus: String) async {
        let ok = await appState.perform { try await $0.updateRequestStatus(id: request.id, status: newStatus) }
        if ok { status = newStatus }
    }
}

private struct MessageBubble: View {
    let message: Message
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(mine ? Theme.accent : Color(.secondarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(mine ? .white : .primary)
            if !mine { Spacer(minLength: 40) }
        }
    }
}
