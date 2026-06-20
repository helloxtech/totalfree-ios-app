import SwiftUI
import PhotosUI
import CoreLocation
import UIKit

/// My posts — the listings I've shared. Posting also happens here (+ button).
struct MyStuffView: View {
    @EnvironmentObject private var appState: AppState
    @State private var listings: [Listing] = []
    @State private var loading = false
    @State private var showPost = false
    @State private var statusFilter = "all"
    @State private var showOffers = true
    @State private var showWanted = true

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
                            Section {
                                if showOffers { ForEach(offers) { postRow($0) } }
                            } header: {
                                collapsibleHeader("Giving away", count: offers.count, expanded: $showOffers)
                            }
                        }
                        if !wanted.isEmpty {
                            Section {
                                if showWanted { ForEach(wanted) { postRow($0) } }
                            } header: {
                                collapsibleHeader("Wanted", count: wanted.count, expanded: $showWanted)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .top) {
                        VStack(spacing: 0) {
                            if appState.myPostsActionableCount > 0 { actionableBanner }
                            statusBar
                        }
                    }
                    .overlay {
                        if filtered.isEmpty {
                            EmptyState(
                                title: "Nothing in this filter",
                                message: "No posts match this status. Try a different filter.",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        }
                    }
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

    private var statusBar: some View {
        Picker("Status", selection: $statusFilter) {
            Text("All").tag("all")
            Text("Active").tag("active")
            Text("Pickup").tag("claimed")
            Text("In review").tag("pending_review")
            Text("Closed").tag("closed")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // Explains the number on the My Posts tab badge (rejected posts need a fix).
    private var actionableBanner: some View {
        let n = appState.myPostsActionableCount
        return Button {
            withAnimation { statusFilter = "closed" }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("\(n) post\(n == 1 ? " was" : "s were") rejected — tap to review & resubmit")
                    .font(.caption).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Tappable section header that collapses its rows.
    private func collapsibleHeader(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack {
                Text("\(title) (\(count))")
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2.bold())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Posts narrowed to the selected status. "Closed" = rejected / withdrawn / completed.
    private var filtered: [Listing] {
        switch statusFilter {
        case "active": return listings.filter { $0.status == "active" }
        case "claimed": return listings.filter { $0.status == "claimed" }
        case "pending_review": return listings.filter { $0.status == "pending_review" }
        case "closed": return listings.filter { ["rejected", "removed", "completed", "archived"].contains($0.status) }
        default: return listings
        }
    }
    private var offers: [Listing] { filtered.filter { $0.listingKind != "wanted" } }
    private var wanted: [Listing] { filtered.filter { $0.listingKind == "wanted" } }

    private func postRow(_ listing: Listing) -> some View {
        NavigationLink { ListingDetailView(listing: listing) } label: { ListingCard(listing: listing) }
    }

    private func reload() async {
        guard let uid = appState.userId else { return }
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchMyListings(ownerId: uid) }) { listings = r }
        await appState.refreshMyPostsCount()
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
                    List(groups) { group in
                        NavigationLink {
                            ListingRequestersView(group: group)
                        } label: {
                            MessageGroupRow(group: group, userId: appState.userId,
                                            unread: group.requests.contains { appState.conversationHasUnread($0.id) })
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

    /// Conversations grouped by item: one row per listing, newest activity first.
    /// One conversation opens its thread directly; several open a per-person list.
    private var groups: [MessageGroup] {
        Dictionary(grouping: requests, by: \.listingId)
            .map { listingId, rows in
                MessageGroup(listingId: listingId,
                             requests: rows.sorted { ($0.latestActivityAt ?? "") > ($1.latestActivityAt ?? "") })
            }
            .sorted { ($0.latestActivityAt ?? "") > ($1.latestActivityAt ?? "") }
    }
}

/// Conversations for one item, grouped so several requesters don't show as
/// duplicate rows under the same title.
private struct MessageGroup: Identifiable {
    let listingId: String
    let requests: [AppRequest]
    var id: String { listingId }
    var title: String { requests.first?.itemTitle ?? "Listing" }
    var imageUrl: String? { requests.first?.listings?.imageUrl }
    var prefersContainedImage: Bool { requests.first?.listings?.prefersContainedImage ?? false }
    var latestActivityAt: String? { requests.first?.latestActivityAt }
    var count: Int { requests.count }
}

/// One row in Messages — the item, who's involved, and a count when several
/// neighbours are talking about the same post.
private struct MessageGroupRow: View {
    let group: MessageGroup
    let userId: String?
    let unread: Bool

    var body: some View {
        HStack(spacing: 12) {
            ListingThumb(url: group.imageUrl, size: 48, contained: group.prefersContainedImage)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title)
                        .font(.subheadline.weight(unread ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer()
                    if group.count > 1 {
                        Text("\(group.count) people")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    } else if let only = group.requests.first {
                        StatusBadge(status: only.status)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if group.count == 1, let only = group.requests.first, !only.message.isEmpty {
                    Text(only.message).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            if unread { Circle().fill(Theme.accent).frame(width: 9, height: 9) }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        guard let latest = group.requests.first else { return "" }
        if group.count > 1 {
            return "\(group.count) conversations · \(relativeDate(group.latestActivityAt))"
        }
        let incoming = latest.ownerId == userId
        return incoming
            ? "From \(latest.requesterName) · \(relativeDate(latest.latestActivityAt))"
            : "To \(latest.ownerName) · \(relativeDate(latest.latestActivityAt))"
    }
}

/// Per-person conversation list, shown when one item has several requesters.
private struct ListingRequestersView: View {
    @EnvironmentObject private var appState: AppState
    let group: MessageGroup

    var body: some View {
        List(group.requests) { req in
            NavigationLink {
                RequestThreadView(request: req)
            } label: {
                RequesterRow(request: req,
                             isIncoming: req.ownerId == appState.userId,
                             unread: appState.conversationHasUnread(req.id))
            }
        }
        .listStyle(.plain)
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RequesterRow: View {
    let request: AppRequest
    let isIncoming: Bool
    let unread: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(isIncoming ? "Received" : "Sent",
                          systemImage: isIncoming ? "tray.and.arrow.down" : "paperplane")
                        .font(.caption2.bold())
                        .foregroundStyle(isIncoming ? Theme.accent : .blue)
                    Spacer()
                    StatusBadge(status: request.status)
                }
                Text(isIncoming ? "From \(request.requesterName)" : "To \(request.ownerName)")
                    .font(.subheadline.weight(unread ? .bold : .semibold))
                    .lineLimit(1)
                if !request.message.isEmpty {
                    Text(request.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if unread { Circle().fill(Theme.accent).frame(width: 9, height: 9) }
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
    @State private var confirmComplete = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showLocationPicker = false
    @State private var sending = false

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
            .scrollDismissesKeyboard(.interactively)
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
        .confirmationDialog("Mark this as picked up?", isPresented: $confirmComplete, titleVisibility: .visible) {
            Button("Mark picked up") { Task { await setStatus("completed") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this after the item has changed hands. You can reopen the pickup if needed.")
        }
    }

    /// Owner controls — decisions can be changed (Accepted ↔ Declined) any time.
    private var manageBar: some View {
        HStack(spacing: 10) {
            if status == "pending" || status == "declined" {
                Button { Task { await setStatus("accepted") } } label: {
                    Label(status == "declined" ? "Accept pickup" : "Accept pickup", systemImage: "checkmark").frame(maxWidth: .infinity)
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
                    Label("Mark picked up", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
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
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }
                Button { showLocationPicker = true } label: { Label("Location", systemImage: "mappin.and.ellipse") }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.secondary)
            }
            .disabled(sending)

            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)

            if sending {
                ProgressView().frame(width: 28)
            } else {
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(.bar)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 6, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await sendImages(items) }
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(initial: defaultCoordinate) { picked in
                Task { await sendLocation(picked) }
            }
        }
    }

    private var defaultCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 49.22, longitude: -122.95) // Metro Vancouver
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

    /// Send one gallery message with up to six photos.
    private func sendImages(_ items: [PhotosPickerItem]) async {
        guard let uid = appState.userId else { return }
        sending = true
        defer { sending = false; photoItems = [] }
        var urls: [String] = []
        for item in items.prefix(6) {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            let data = UIImage(data: raw)?.jpegResized(maxDimension: 1280, quality: 0.8) ?? raw
            if let url = await appState.load({ try await $0.uploadImage(data, contentType: "image/jpeg", ext: "jpg", userId: uid) }) {
                urls.append(url)
            }
        }
        guard !urls.isEmpty else { return }
        let ok = await appState.perform {
            try await $0.sendMessage(requestId: request.id, text: "", senderId: uid, kind: "image", imageUrls: urls)
        }
        if ok { await loadMessages() }
    }

    /// Send a map-picked location as a tappable Apple Maps link.
    private func sendLocation(_ picked: PickedLocation) async {
        guard let uid = appState.userId else { return }
        let lat = picked.coordinate.latitude, lng = picked.coordinate.longitude
        let candidates = [picked.area, picked.city].compactMap { $0 }.filter { !$0.isEmpty }
        let place = candidates.first ?? "Shared location"
        let text = place
        sending = true
        defer { sending = false }
        let ok = await appState.perform {
            try await $0.sendMessage(requestId: request.id, text: text, senderId: uid, kind: "location", lat: lat, lng: lng)
        }
        if ok { await loadMessages() }
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
            content
            if !mine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var content: some View {
        if !galleryURLs.isEmpty {
            gallery
        } else if let loc = locationLink {
            Link(destination: loc.url) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                    Text(loc.label).font(.subheadline).lineLimit(2)
                    Image(systemName: "arrow.up.right.square").font(.caption2)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(mine ? Theme.accent : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(mine ? .white : .primary)
            }
        } else {
            textBubble
        }
    }

    private var gallery: some View {
        let columns = galleryURLs.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(galleryURLs, id: \.self) { url in
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: galleryURLs.count == 1 ? 220 : 108, height: galleryURLs.count == 1 ? 180 : 108)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: 224)
    }

    private var textBubble: some View {
        Text(message.text)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(mine ? Theme.accent : Color(.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(mine ? .white : .primary)
    }

    private var galleryURLs: [URL] {
        let urls = message.galleryUrls.compactMap(URL.init(string:))
        if !urls.isEmpty { return urls }
        if let legacy = legacyImageURL { return [legacy] }
        return []
    }

    /// Back-compat: older iOS sent image URLs as plain text.
    private var legacyImageURL: URL? {
        let t = message.text.lowercased()
        guard t.contains("/storage/v1/object/public/"),
              t.hasSuffix(".jpg") || t.hasSuffix(".jpeg") || t.hasSuffix(".png"),
              let u = URL(string: message.text) else { return nil }
        return u
    }

    /// A message carrying an Apple Maps link → render a tappable location chip.
    private var locationLink: (label: String, url: URL)? {
        if message.kind == "location", let lat = message.lat, let lng = message.lng {
            let label = message.text.isEmpty ? "View location" : message.text
            let q = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(q)") else { return nil }
            return (label, url)
        }
        guard let r = message.text.range(of: "https://maps.apple.com/") else { return nil }
        let urlStr = String(message.text[r.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: urlStr) else { return nil }
        let label = message.text[..<r.lowerBound]
            .replacingOccurrences(of: "📍", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (label.isEmpty ? "View location" : label, u)
    }
}
