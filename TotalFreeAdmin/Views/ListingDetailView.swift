import SwiftUI

struct ListingDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var listing: Listing

    @State private var showRequest = false
    @State private var showReport = false
    @State private var showAuth = false
    @State private var showEdit = false
    @State private var confirmDelete = false

    private var isOwner: Bool { listing.ownerId != nil && listing.ownerId == appState.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gallery

                HStack(spacing: 6) {
                    if listing.isWanted {
                        Text("WANTED").font(.caption.bold()).foregroundStyle(.blue)
                    }
                    SourceBadge(sourceType: listing.sourceType)
                    StatusBadge(status: listing.status)
                    if listing.byDonation == true {
                        Text("By donation").font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                }

                Text(listing.title).font(.title2.bold())

                HStack(spacing: 10) {
                    CategoryChip(category: listing.category)
                    if let cond = listing.conditionLabel {
                        Label(cond, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    }
                    Label(listing.locationText, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !listing.description.isEmpty {
                    Text(listing.description).font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("From \(listing.sourceLabelText)", systemImage: "person.circle")
                        .font(.subheadline)
                    if let created = listing.createdAt {
                        Text("Posted \(relativeDate(created))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                actions

                if let url = listing.externalUrl, let u = URL(string: url) {
                    Link(destination: u) {
                        Label("Open on provider's site", systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .navigationTitle(listing.isWanted ? "Wanted" : "Free item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) { ownerMenu }
            }
        }
        .sheet(isPresented: $showRequest) { RequestSheet(listing: listing) }
        .sheet(isPresented: $showReport) { ReportSheet(listing: listing) }
        .sheet(isPresented: $showAuth) { AuthView() }
        .sheet(isPresented: $showEdit) {
            EditListingView(listing: listing, resubmitOnSave: true) { listing = $0 }
        }
        .confirmationDialog("Delete this listing?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteSelf() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the post.")
        }
        .task { await refresh() }
    }

    // MARK: Photo gallery

    @ViewBuilder
    private var gallery: some View {
        let urls = listing.galleryUrls
        if urls.count > 1 {
            TabView {
                ForEach(urls, id: \.self) { url in
                    AsyncImage(url: URL(string: url)) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Rectangle().fill(Color(.secondarySystemFill)) }
                    }
                    .clipped()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if let url = urls.first, let u = URL(string: url) {
            AsyncImage(url: u) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.secondarySystemFill))
                        .overlay { Image(systemName: "gift").font(.largeTitle).foregroundStyle(.secondary) }
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: Owner controls

    @ViewBuilder
    private var ownerMenu: some View {
        Menu {
            if appState.can(Perm.listingEditOwn) {
                Button {
                    showEdit = true
                } label: {
                    Label(listing.status == "rejected" ? "Edit & resubmit" : "Edit", systemImage: "pencil")
                }
            }
            if listing.status == "pending_review" {
                Button { Task { await setStatus("removed") } } label: { Label("Withdraw", systemImage: "arrow.uturn.backward") }
            }
            if listing.status == "active" {
                Button { Task { await setStatus("completed") } } label: { Label("Mark completed", systemImage: "checkmark.circle") }
            }
            if appState.can(Perm.listingDeleteOwn) {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isOwner {
            InfoCallout(
                title: ownerCalloutTitle,
                message: ownerCalloutMessage,
                systemImage: "checkmark.seal"
            )
        } else if listing.status == "active" {
            VStack(spacing: 10) {
                Button {
                    if appState.isAuthed { showRequest = true } else { showAuth = true }
                } label: {
                    Label(listing.isWanted ? "Offer to help" : "Ask for this", systemImage: "hand.raised")
                        .bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    if appState.isAuthed { showReport = true } else { showAuth = true }
                } label: {
                    Label("Report this listing", systemImage: "flag").font(.subheadline)
                }
            }
        }
    }

    private var ownerCalloutTitle: String {
        switch listing.status {
        case "pending_review": "Waiting for review"
        case "rejected": "This post was rejected"
        case "active": "This is your listing"
        case "completed": "Marked completed"
        case "removed": "Withdrawn"
        default: "Your listing"
        }
    }
    private var ownerCalloutMessage: String {
        switch listing.status {
        case "pending_review": "A moderator will review it soon. Use the ⋯ menu to edit or withdraw it."
        case "rejected": "Tap ⋯ → Edit & resubmit to fix it and send it back for review."
        case "active": "You'll get an alert when a neighbour requests it. Use ⋯ to manage it."
        default: "Use the ⋯ menu to manage this post."
        }
    }

    // MARK: Actions

    private func refresh() async {
        if let fresh = (await appState.load { try await $0.fetchListing(id: listing.id) }) ?? nil {
            listing = fresh
        }
    }

    private func setStatus(_ status: String) async {
        let ok = await appState.perform { try await $0.setListingStatus(id: listing.id, status: status) }
        if ok {
            appState.infoMessage = status == "completed" ? "Marked completed." : "Listing withdrawn."
            await refresh()
        }
    }

    private func deleteSelf() async {
        let ok = await appState.perform { try await $0.deleteListing(id: listing.id) }
        if ok {
            appState.infoMessage = "Listing deleted."
            dismiss()
        }
    }
}

// MARK: - Request sheet

private struct RequestSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let listing: Listing
    @State private var message = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add a short, friendly message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Message to \(listing.sourceLabelText)")
                } footer: {
                    Text("Keep it kind. No addresses or phone numbers in public — arrange details in the private chat after they accept.")
                }
            }
            .navigationTitle(listing.isWanted ? "Offer to help" : "Ask for this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }.disabled(sending || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        guard let uid = appState.userId else { return }
        sending = true
        Task {
            let ok = await appState.perform {
                try await $0.createRequest(
                    listingId: listing.id, ownerId: listing.ownerId,
                    message: message.trimmingCharacters(in: .whitespaces), requesterId: uid
                )
            }
            sending = false
            if ok {
                appState.infoMessage = "Sent — you'll hear back in Messages."
                dismiss()
            }
        }
    }
}

// MARK: - Report sheet

private struct ReportSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let listing: Listing

    private let reasons: [(key: String, label: String)] = [
        ("spam", "Spam or scam"),
        ("prohibited", "Prohibited or unsafe item"),
        ("payment", "Asking for payment"),
        ("wrong_info", "Wrong or misleading info"),
        ("other", "Something else"),
    ]
    @State private var reason = "spam"
    @State private var note = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons.indices, id: \.self) { i in
                            Text(reasons[i].label).tag(reasons[i].key)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Add detail (optional)") {
                    TextField("What's wrong?", text: $note, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Report listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }.disabled(sending)
                }
            }
        }
    }

    private func submit() {
        sending = true
        Task {
            let ok = await appState.perform {
                try await $0.reportListing(
                    listingId: listing.id, reason: reason,
                    note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
                )
            }
            sending = false
            if ok {
                appState.infoMessage = "Thanks — our moderators will take a look."
                dismiss()
            }
        }
    }
}
