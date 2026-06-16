import SwiftUI

/// Staff moderation queue — listings awaiting review (status `pending_review`).
/// Pushed inside the Admin tab's NavigationStack, so it adds no stack of its own.
struct ModerationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var queue: [Listing] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && queue.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if queue.isEmpty {
                EmptyState(title: "Queue is clear", message: "No listings are waiting for review. Nice work.", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(queue) { listing in
                        NavigationLink {
                            ModerationDetailView(listing: listing) { await reload() }
                        } label: {
                            ListingCard(listing: listing)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { Task { await moderate(listing, "rejected") } } label: {
                                Label("Reject", systemImage: "xmark")
                            }.tint(.red)
                            Button { Task { await moderate(listing, "active") } } label: {
                                Label("Approve", systemImage: "checkmark")
                            }.tint(.green)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Moderation")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchModerationQueue() }) { queue = r }
        await appState.refreshStaffCounts()
    }

    private func moderate(_ listing: Listing, _ status: String) async {
        let ok = await appState.perform { try await $0.moderateListing(id: listing.id, status: status) }
        if ok {
            queue.removeAll { $0.id == listing.id }
            appState.infoMessage = status == "active" ? "Listing approved." : "Listing rejected."
            await appState.refreshStaffCounts()
        }
    }
}

/// Full preview of a pending listing with Approve / Reject.
struct ModerationDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var listing: Listing
    let onResolved: () async -> Void

    @State private var confirmReject = false
    @State private var working = false
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = listing.imageUrl, !url.isEmpty {
                    Color(.secondarySystemFill)
                        .overlay {
                            AsyncImage(url: URL(string: url)) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() }
                                else if phase.error != nil { Image(systemName: "photo").foregroundStyle(.secondary) }
                                else { ProgressView() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                HStack { SourceBadge(sourceType: listing.sourceType); if listing.isWanted { Text("WANTED").font(.caption.bold()).foregroundStyle(.blue) } }
                Text(listing.title).font(.title3.bold())
                HStack(spacing: 10) {
                    CategoryChip(category: listing.category)
                    Label(listing.locationText, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                }
                if let cond = listing.conditionLabel { Text("Condition: \(cond)").font(.subheadline) }
                if !listing.description.isEmpty { Text(listing.description) }
                Text("Posted by \(listing.ownerName ?? "a member") · \(relativeDate(listing.createdAt))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appState.can(Perm.listingEditAny) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditListingView(listing: listing) { listing = $0 }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(role: .destructive) { confirmReject = true } label: {
                    Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { Task { await moderate("active") } } label: {
                    Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
            .disabled(working)
        }
        .confirmationDialog("Reject this listing?", isPresented: $confirmReject, titleVisibility: .visible) {
            Button("Reject", role: .destructive) { Task { await moderate("rejected") } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func moderate(_ status: String) async {
        working = true
        let ok = await appState.perform { try await $0.moderateListing(id: listing.id, status: status) }
        working = false
        if ok {
            appState.infoMessage = status == "active" ? "Listing approved." : "Listing rejected."
            await onResolved()
            dismiss()
        }
    }
}
