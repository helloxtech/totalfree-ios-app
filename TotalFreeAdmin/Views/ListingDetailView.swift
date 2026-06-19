import SwiftUI
import MapKit
import CoreLocation

struct ListingDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var listing: Listing

    @State private var showRequest = false
    @State private var showReport = false
    @State private var showAuth = false
    @State private var showEdit = false
    @State private var showClaim = false
    @State private var confirmDelete = false
    @State private var geocoded: CLLocationCoordinate2D?

    private var isOwner: Bool { listing.ownerId != nil && listing.ownerId == appState.userId }
    private var sourceURL: URL? {
        guard let raw = listing.externalUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(string: "https://\(raw)")
    }
    private var usesExternalSourceAction: Bool {
        listing.ownerId == nil && ["partner", "sponsored"].contains(listing.sourceType)
    }
    private var canClaim: Bool {
        listing.ownerId == nil && ["partner", "external"].contains(listing.sourceType)
    }

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
                    if let coord = mapCoordinate {
                        Button { openInMaps(coord) } label: {
                            Label(listing.locationText, systemImage: "mappin.and.ellipse").font(.caption)
                        }
                    } else {
                        Label(listing.locationText, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

                if let coord = mapCoordinate {
                    mapPreview(coord)
                }

                actions

                if !usesExternalSourceAction, let u = sourceURL {
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
        .sheet(isPresented: $showClaim) {
            ClaimListingSheet(listing: listing) {
                await refresh()
            }
        }
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
        .task { await geocodeIfNeeded() }
        .onChange(of: listing.status) { _, _ in
            // Resubmitting or withdrawing a rejected post should clear the My Posts
            // tab badge right away, not on next app launch.
            Task { await appState.refreshMyPostsCount() }
        }
    }

    // MARK: Photo gallery

    @ViewBuilder
    private var gallery: some View {
        let urls = listing.galleryUrls
        if urls.count > 1 {
            TabView {
                ForEach(urls, id: \.self) { url in photoFill(url) }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else if let url = urls.first {
            photoFill(url)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    // A flexible box (never wider than the screen) filled with the photo. Using a
    // sizer + overlay keeps `scaledToFill` from driving layout width.
    private func photoFill(_ url: String) -> some View {
        Color(.secondarySystemFill)
            .overlay {
                AsyncImage(url: URL(string: url)) { phase in
                    if let img = phase.image { listingImage(img) }
                    else if phase.error != nil { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
                    else { ProgressView() }
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func listingImage(_ image: Image) -> some View {
        if listing.prefersContainedImage {
            image
                .resizable()
                .scaledToFit()
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Location / map

    private var mapCoordinate: CLLocationCoordinate2D? {
        if let lat = listing.lat, let lng = listing.lng { return CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        return geocoded
    }

    private func mapPreview(_ coord: CLLocationCoordinate2D) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))) {
            Marker(listing.locationText, coordinate: coord).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .overlay(alignment: .bottomTrailing) {
            Button { openInMaps(coord) } label: {
                Label("Open in Maps", systemImage: "arrow.up.right.square")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .padding(8)
        }
    }

    private func openInMaps(_ c: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = listing.locationText
        item.openInMaps()
    }

    private func geocodeIfNeeded() async {
        guard listing.lat == nil || listing.lng == nil, geocoded == nil else { return }
        let parts = [listing.area, listing.city].compactMap { ($0?.isEmpty == false) ? $0 : nil }
        guard !parts.isEmpty else { return }
        let query = (parts + ["BC, Canada"]).joined(separator: ", ")
        if let placemarks = try? await CLGeocoder().geocodeAddressString(query),
           let loc = placemarks.first?.location {
            geocoded = loc.coordinate
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
                    Label((listing.status == "rejected" || listing.status == "archived") ? "Edit & resubmit" : "Edit", systemImage: "pencil")
                }
            }
            if listing.status == "pending_review" {
                Button { Task { await setStatus("removed") } } label: { Label("Withdraw", systemImage: "arrow.uturn.backward") }
            }
            if listing.status == "rejected" {
                // Archive a rejected post: hide it (clears the My Posts badge) without
                // deleting. It stays under Closed and can still be edited & resubmitted.
                Button { Task { await archive() } } label: { Label("Archive", systemImage: "archivebox") }
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
                if usesExternalSourceAction {
                    if let u = sourceURL {
                        Link(destination: u) {
                            Label("View original source", systemImage: "arrow.up.right.square")
                                .bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        InfoCallout(
                            title: "Source contact unavailable",
                            message: "This \(AppConstants.sourceLabel(listing.sourceType).lowercased()) listing is not claimed yet.",
                            systemImage: "link.badge.plus"
                        )
                    }
                } else {
                    Button {
                        if !appState.isAuthed {
                            showAuth = true
                        } else if !appState.isVerified {
                            appState.infoMessage = "Please confirm your email before sending requests."
                        } else {
                            showRequest = true
                        }
                    } label: {
                        Label(listing.isWanted ? "Offer to help" : "Ask for this", systemImage: "hand.raised")
                            .bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    if appState.isAuthed { showReport = true } else { showAuth = true }
                } label: {
                    Label("Report this listing", systemImage: "flag").font(.subheadline)
                }

                if canClaim {
                    Button {
                        if !appState.isAuthed {
                            showAuth = true
                        } else if !appState.isVerified {
                            appState.infoMessage = "Please confirm your email before claiming an organization listing."
                        } else {
                            showClaim = true
                        }
                    } label: {
                        Label("Are you this organization? Claim it", systemImage: "building.2.crop.circle")
                            .font(.subheadline.weight(.semibold))
                    }
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
        case "archived": "Archived"
        default: "Your listing"
        }
    }
    private var ownerCalloutMessage: String {
        switch listing.status {
        case "pending_review": "A moderator will review it soon. Use the ⋯ menu to edit or withdraw it."
        case "rejected": "Tap ⋯ → Edit & resubmit to fix it and send it back for review."
        case "active": "You'll get an alert when a neighbour requests it. Use ⋯ to manage it."
        case "archived": "Hidden from your active posts. Tap ⋯ → Edit & resubmit to send it back for review, or delete it."
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

    private func archive() async {
        let ok = await appState.perform { try await $0.setListingStatus(id: listing.id, status: "archived") }
        if ok {
            appState.infoMessage = "Post archived — find it under Closed."
            await refresh()
        }
    }

    private func deleteSelf() async {
        let ok = await appState.perform { try await $0.deleteListing(id: listing.id) }
        if ok {
            appState.infoMessage = "Listing deleted."
            await appState.refreshMyPostsCount()
            dismiss()
        }
    }
}

// MARK: - Claim sheet

private struct ClaimListingSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let listing: Listing
    var onSubmitted: () async -> Void

    @State private var orgName: String
    @State private var website: String
    @State private var note = ""
    @State private var sending = false

    init(listing: Listing, onSubmitted: @escaping () async -> Void) {
        self.listing = listing
        self.onSubmitted = onSubmitted
        _orgName = State(initialValue: listing.sourceLabel ?? "")
        _website = State(initialValue: listing.externalUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Organization name", text: $orgName)
                        .textInputAutocapitalization(.words)
                    TextField("Official website or program page", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Your role, department, or proof", text: $note, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text("Claim details")
                } footer: {
                    Text("A matching work email may verify instantly. Otherwise moderators use these details to confirm you can manage this organization listing.")
                }

                Section {
                    InfoCallout(
                        title: "What happens next",
                        message: "If the domain does not match, admins will compare your organization name, website, note, and the listing source before approving.",
                        systemImage: "checkmark.seal"
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            }
            .navigationTitle("Claim listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Submitting..." : "Submit") { submit() }
                        .disabled(sending || orgName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
        }
    }

    private func submit() {
        let cleanOrg = orgName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanOrg.count >= 2 else { return }
        sending = true
        Task {
            let result = await appState.load {
                try await $0.claimListing(
                    id: listing.id,
                    orgName: cleanOrg,
                    website: website.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            sending = false
            if let result {
                appState.infoMessage = result == "approved"
                    ? "Verified by email domain. You now manage this listing."
                    : "Claim submitted for review."
                await onSubmitted()
                dismiss()
            }
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
                    Button("Send") { send() }.disabled(sending || !appState.isVerified || message.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        guard let uid = appState.userId else { return }
        guard appState.isVerified else {
            appState.infoMessage = "Please confirm your email before sending requests."
            return
        }
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
