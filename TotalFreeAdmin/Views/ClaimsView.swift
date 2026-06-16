import SwiftUI

/// Organization claims & registrations. Tap a row for detail; swipe to resolve.
/// Gated by claim.resolve.
struct ClaimsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var claims: [OrgClaim] = []
    @State private var loading = false

    private var pending: [OrgClaim] { claims.filter { $0.status == "pending" } }
    private var resolved: [OrgClaim] { claims.filter { $0.status != "pending" } }

    var body: some View {
        Group {
            if loading && claims.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if claims.isEmpty {
                EmptyState(title: "No claims", message: "No organization claims or registrations are waiting.", systemImage: "checkmark.seal")
            } else {
                List {
                    if !pending.isEmpty {
                        Section("Pending (\(pending.count))") {
                            ForEach(pending) { c in
                                row(c).swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { Task { await resolve(c, approve: false) } } label: { Label("Reject", systemImage: "xmark") }
                                    Button { Task { await resolve(c, approve: true) } } label: { Label("Approve", systemImage: "checkmark") }.tint(.green)
                                }
                            }
                        }
                    }
                    if !resolved.isEmpty {
                        Section("Resolved") { ForEach(resolved) { row($0) } }
                    }
                }
            }
        }
        .navigationTitle("Org claims")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func row(_ c: OrgClaim) -> some View {
        NavigationLink {
            ClaimDetailView(claim: c) { await reload() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(c.kind == "register" ? "Register" : "Claim", systemImage: "building.2").font(.caption.bold())
                    Spacer()
                    StatusBadge(status: c.status)
                }
                Text(c.what).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text("By \(c.who)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchPendingClaims() }) { claims = r }
    }

    private func resolve(_ c: OrgClaim, approve: Bool) async {
        let ok = await appState.perform { try await $0.resolveClaim(id: c.id, approve: approve) }
        if ok {
            appState.infoMessage = approve ? "Claim approved." : "Claim rejected."
            await reload()
        }
    }
}

struct ClaimDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let claim: OrgClaim
    var onResolved: () async -> Void
    @State private var working = false

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: claim.kind == "register" ? "New organization" : "Listing claim")
                LabeledContent("Organization", value: claim.what)
                LabeledContent("Requested by", value: claim.who)
                if let site = claim.website, !site.isEmpty { LabeledContent("Website", value: site) }
                if let created = claim.createdAt { LabeledContent("Submitted", value: relativeDate(created)) }
                StatusBadge(status: claim.status)
            }
            if let note = claim.note, !note.isEmpty {
                Section("Note") { Text(note).font(.subheadline) }
            }
            if claim.status == "pending" {
                Section {
                    Button { Task { await resolve(approve: true) } } label: {
                        Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { Task { await resolve(approve: false) } } label: {
                        Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                }
                .disabled(working)
            }
        }
        .navigationTitle("Claim")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolve(approve: Bool) async {
        working = true
        let ok = await appState.perform { try await $0.resolveClaim(id: claim.id, approve: approve) }
        working = false
        if ok {
            appState.infoMessage = approve ? "Claim approved." : "Claim rejected."
            await onResolved()
            dismiss()
        }
    }
}
