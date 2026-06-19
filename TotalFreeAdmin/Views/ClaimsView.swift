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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(c.typeLabel, systemImage: c.kind == "register" ? "building.2.crop.circle" : "checkmark.seal")
                        .font(.caption.bold())
                    ClaimDomainBadge(claim: c)
                    Spacer()
                    StatusBadge(status: c.status)
                }
                Text(c.what)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(rowSummary(c))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if c.hasDomainMismatch {
                    Label("Email domain differs from the reference site", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func rowSummary(_ claim: OrgClaim) -> String {
        var parts: [String] = [claim.email ?? claim.who]
        if let referenceDomain = claim.referenceDomain { parts.append(referenceDomain) }
        if let created = claim.createdAt { parts.append(relativeDate(created)) }
        return parts.joined(separator: " · ")
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
                InfoCallout(
                    title: "What approval means",
                    message: "Approve only when the requester appears authorized. Approval gives this person organization management access and connects the listing when this is a listing claim.",
                    systemImage: "person.badge.shield.checkmark"
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            Section("Decision signal") {
                HStack {
                    ClaimDomainBadge(claim: claim)
                    Spacer()
                    StatusBadge(status: claim.status)
                }
                ClaimChecklistLine(
                    title: domainMessage,
                    systemImage: claim.hasDomainMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: claim.hasDomainMatch ? .green : .orange
                )
            }

            Section("Claim") {
                ClaimDetailRow(label: "Type", value: claim.typeLabel)
                ClaimDetailRow(label: "Submitted", value: claim.createdAt.map(relativeDate) ?? "Unknown")
                ClaimDetailRow(label: "Organization", value: claim.orgName ?? "Not provided", isWarning: claim.orgName == nil)
            }

            Section("Requester") {
                ClaimDetailRow(label: "Name", value: claim.who)
                ClaimDetailRow(label: "Email", value: claim.email ?? "Not available", isWarning: claim.email == nil)
                ClaimDetailRow(label: "Email domain", value: claim.emailDomain ?? "Not available", isWarning: claim.emailDomain == nil)
            }

            Section("Organization and listing") {
                ClaimDetailRow(label: "Website", value: claim.website?.isEmpty == false ? claim.website! : "Not provided", isWarning: claim.website?.isEmpty != false)
                ClaimDetailRow(label: "Reference domain", value: claim.referenceDomain ?? "Not available", isWarning: claim.referenceDomain == nil)
                if let listing = claim.listingDisplay { ClaimDetailRow(label: "Listing", value: listing) }
                if let source = claim.listingSourceLabel, !source.isEmpty { ClaimDetailRow(label: "Source", value: source) }
                if let sourceUrl = claim.listingExternalUrl, let url = reviewURL(sourceUrl) {
                    Link("Open listing source", destination: url)
                }
                if let site = claim.website, let url = reviewURL(site) {
                    Link("Open organization website", destination: url)
                }
            }

            if let note = claim.note, !note.isEmpty {
                Section("Evidence note") { Text(note).font(.subheadline) }
            } else {
                Section("Evidence note") {
                    ClaimChecklistLine(
                        title: "No note was provided. Ask for more proof if the domain check is missing or unclear.",
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            }

            Section("Review before approving") {
                ClaimChecklistLine(title: "Confirm the requester belongs to the organization.", systemImage: "person.crop.circle.badge.checkmark", color: Theme.accent)
                ClaimChecklistLine(title: "Open the listing or source and confirm it represents the same organization.", systemImage: "link", color: Theme.accent)
                ClaimChecklistLine(title: "Reject if ownership is unclear or the evidence does not match.", systemImage: "xmark.seal", color: .red)
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

    private var domainMessage: String {
        if claim.hasDomainMatch {
            return "Requester email domain matches the reference site."
        }
        if claim.hasDomainMismatch {
            return "Requester email domain does not match the reference site. Verify manually before approving."
        }
        return "No domain match is available. Use the note, website, and source before deciding."
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

private struct ClaimDomainBadge: View {
    let claim: OrgClaim

    var body: some View {
        Label(claim.domainStatus, systemImage: icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private var icon: String {
        claim.hasDomainMatch ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var color: Color {
        if claim.hasDomainMatch { return .green }
        if claim.hasDomainMismatch { return .orange }
        return .secondary
    }
}

private struct ClaimDetailRow: View {
    let label: String
    let value: String
    var isWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(isWarning ? .orange : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct ClaimChecklistLine: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
    }
}

private func reviewURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), url.scheme != nil { return url }
    return URL(string: "https://\(trimmed)")
}
