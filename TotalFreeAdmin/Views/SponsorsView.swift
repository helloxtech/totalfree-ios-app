import SwiftUI

/// Business (sponsor) profiles. Tap a row for detail; swipe to approve/reject.
/// Gated by business.approve.
struct SponsorsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var sponsors: [Sponsor] = []
    @State private var loading = false

    private var pending: [Sponsor] { sponsors.filter { $0.status == "pending_review" } }
    private var others: [Sponsor] { sponsors.filter { $0.status != "pending_review" } }

    var body: some View {
        Group {
            if loading && sponsors.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sponsors.isEmpty {
                EmptyState(title: "No businesses", message: "No business profiles have been submitted yet.", systemImage: "building.2")
            } else {
                List {
                    if !pending.isEmpty {
                        Section("Awaiting approval (\(pending.count))") {
                            ForEach(pending) { s in
                                row(s).swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { Task { await setStatus(s, "rejected") } } label: { Label("Reject", systemImage: "xmark") }
                                    Button { Task { await setStatus(s, "active") } } label: { Label("Approve", systemImage: "checkmark") }.tint(.green)
                                }
                            }
                        }
                    }
                    if !others.isEmpty {
                        Section("All businesses") { ForEach(others) { row($0) } }
                    }
                }
            }
        }
        .navigationTitle("Businesses")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func row(_ s: Sponsor) -> some View {
        NavigationLink {
            SponsorDetailView(sponsor: s) { await reload() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.businessName).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer()
                    StatusBadge(status: s.status)
                }
                if let w = s.website, !w.isEmpty { Text(w).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            }
            .padding(.vertical, 2)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchSponsorsForReview() }) { sponsors = r }
    }

    private func setStatus(_ s: Sponsor, _ status: String) async {
        let ok = await appState.perform { try await $0.updateSponsorStatus(id: s.id, status: status) }
        if ok {
            appState.infoMessage = "Business set to \(status.replacingOccurrences(of: "_", with: " "))."
            await reload()
        }
    }
}

struct SponsorDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let sponsor: Sponsor
    var onResolved: () async -> Void
    @State private var working = false

    var body: some View {
        List {
            Section {
                Text(sponsor.businessName).font(.headline)
                StatusBadge(status: sponsor.status)
                if let w = sponsor.website, !w.isEmpty {
                    if let u = URL(string: w.hasPrefix("http") ? w : "https://\(w)") {
                        Link(destination: u) { Label(w, systemImage: "globe") }
                    } else {
                        LabeledContent("Website", value: w)
                    }
                }
                if let created = sponsor.createdAt { LabeledContent("Submitted", value: relativeDate(created)) }
            }
            if let d = sponsor.description, !d.isEmpty {
                Section("About") { Text(d).font(.subheadline) }
            }
            Section {
                if sponsor.status != "active" {
                    Button { Task { await setStatus("active") } } label: {
                        Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if sponsor.status == "pending_review" {
                    Button(role: .destructive) { Task { await setStatus("rejected") } } label: {
                        Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                } else if sponsor.status == "active" {
                    Button { Task { await setStatus("paused") } } label: {
                        Label("Pause", systemImage: "pause").frame(maxWidth: .infinity)
                    }
                }
            }
            .disabled(working)
        }
        .navigationTitle("Business")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setStatus(_ status: String) async {
        working = true
        let ok = await appState.perform { try await $0.updateSponsorStatus(id: sponsor.id, status: status) }
        working = false
        if ok {
            appState.infoMessage = "Business set to \(status.replacingOccurrences(of: "_", with: " "))."
            await onResolved()
            dismiss()
        }
    }
}
