import SwiftUI

struct MyStuffView: View {
    @EnvironmentObject private var appState: AppState
    enum Tab: String, CaseIterable { case listings = "My posts", requests = "Messages" }

    @State private var tab: Tab = .listings
    @State private var listings: [Listing] = []
    @State private var requests: [AppRequest] = []
    @State private var loading = false
    @State private var showPost = false

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isAuthed {
                    SignInPrompt(
                        title: "Your stuff lives here",
                        message: "Sign in to see your posts, requests, and messages.",
                        systemImage: "shippingbox"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle("My Stuff")
            .toolbar {
                if appState.isAuthed {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showPost = true } label: { Label("New post", systemImage: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showPost, onDismiss: { Task { await reload() } }) {
                PostView(asSheet: true)
            }
            .task { await reload() }
            .onChange(of: tab) { _, _ in Task { await reload() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && listings.isEmpty && requests.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch tab {
            case .listings:
                if listings.isEmpty {
                    EmptyState(title: "No posts yet", message: "Items you post will show here with their review status.", systemImage: "shippingbox")
                } else {
                    List(listings) { listing in
                        NavigationLink { ListingDetailView(listing: listing) } label: { ListingCard(listing: listing) }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            case .requests:
                if requests.isEmpty {
                    EmptyState(title: "No messages yet", message: "When you ask for an item or someone asks about your post, the conversation shows here.", systemImage: "bubble.left.and.bubble.right")
                } else {
                    List(requests) { req in
                        NavigationLink { RequestThreadView(request: req) } label: {
                            RequestRow(request: req, isIncoming: req.ownerId == appState.userId)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                }
            }
        }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        switch tab {
        case .listings:
            if let r = await appState.load({ try await $0.fetchMyListings(ownerId: uid) }) { listings = r }
        case .requests:
            if let r = await appState.load({ try await $0.fetchMyRequests(userId: uid) }) { requests = r }
        }
    }
}

private struct RequestRow: View {
    let request: AppRequest
    let isIncoming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(isIncoming ? "Received" : "Sent", systemImage: isIncoming ? "tray.and.arrow.down" : "paperplane")
                    .font(.caption2.bold())
                    .foregroundStyle(isIncoming ? Theme.accent : .blue)
                Spacer()
                StatusBadge(status: request.status)
            }
            Text(request.itemTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
            if !request.message.isEmpty {
                Text(request.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
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

    init(request: AppRequest, readOnly: Bool = false) {
        self.request = request
        self.readOnly = readOnly
        _status = State(initialValue: request.status)
    }

    private var isIncoming: Bool { request.ownerId == appState.userId }

    var body: some View {
        VStack(spacing: 0) {
            if !readOnly && isIncoming && status == "pending" {
                decisionBar
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
        .navigationTitle(request.itemTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { StatusBadge(status: status) }
        }
        .task { await loadMessages() }
        .refreshable { await loadMessages() }
    }

    private var decisionBar: some View {
        HStack(spacing: 10) {
            Button { Task { await setStatus("accepted") } } label: {
                Label("Accept", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button(role: .destructive) { Task { await setStatus("declined") } } label: {
                Label("Decline", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
            if isIncoming && status == "accepted" {
                Button("Done") { Task { await setStatus("completed") } }
                    .font(.caption)
            }
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
