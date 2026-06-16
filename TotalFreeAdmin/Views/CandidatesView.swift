import SwiftUI

/// Scanner finds awaiting review (`listing_candidates`, status needs_review).
/// Tap a row for the full find; swipe to approve/reject. Gated by listing.review.
struct CandidatesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var candidates: [ScanCandidate] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && candidates.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                EmptyState(title: "Nothing to review", message: "The scanners haven't queued any finds for review.", systemImage: "sparkle.magnifyingglass")
            } else {
                List {
                    ForEach(candidates) { c in
                        NavigationLink {
                            CandidateDetailView(candidate: c) { await reload() }
                        } label: {
                            summary(c)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { await review(c, approve: false) } } label: { Label("Reject", systemImage: "xmark") }
                            Button { Task { await review(c, approve: true) } } label: { Label("Approve", systemImage: "checkmark") }.tint(.green)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Scanner finds")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func summary(_ c: ScanCandidate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                if let pct = c.confidencePct {
                    Text(pct).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                }
            }
            HStack(spacing: 8) {
                if let agent = c.agent { Label(agent, systemImage: "cpu").font(.caption2).foregroundStyle(.secondary) }
                if let city = c.payload?.city { Label(city, systemImage: "mappin").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchScanCandidates() }) { candidates = r }
    }

    private func review(_ c: ScanCandidate, approve: Bool) async {
        let ok = await appState.perform { try await $0.reviewScanCandidate(id: c.id, approve: approve, reason: nil) }
        if ok {
            candidates.removeAll { $0.id == c.id }
            appState.infoMessage = approve ? "Published to the site." : "Find rejected."
        }
    }
}

struct CandidateDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let candidate: ScanCandidate
    var onResolved: () async -> Void
    @State private var working = false

    var body: some View {
        List {
            Section {
                Text(candidate.title).font(.headline)
                if let agent = candidate.agent { LabeledContent("Found by", value: agent) }
                if let pct = candidate.confidencePct { LabeledContent("Confidence", value: pct) }
                if let dom = candidate.sourceDomain { LabeledContent("Source", value: dom) }
                if let created = candidate.createdAt { LabeledContent("Queued", value: relativeDate(created)) }
            }
            if let p = candidate.payload {
                Section("Proposed listing") {
                    if let city = p.city { LabeledContent("Area", value: [p.area, city].compactMap { $0 }.first ?? city) }
                    if let cat = p.category { LabeledContent("Category", value: AppConstants.categoryLabel(cat)) }
                    if let desc = p.description, !desc.isEmpty { Text(desc).font(.subheadline) }
                }
            }
            if let q = candidate.evidenceQuote, !q.isEmpty {
                Section("Evidence") { Text("“\(q)”").font(.subheadline).italic() }
            }
            if let link = candidate.payload?.link, let u = URL(string: link) {
                Section { Link(destination: u) { Label("Open source page", systemImage: "arrow.up.right.square") } }
            }
            Section {
                Button { Task { await review(approve: true) } } label: {
                    Label("Approve & publish", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) { Task { await review(approve: false) } } label: {
                    Label("Reject", systemImage: "xmark").frame(maxWidth: .infinity)
                }
            }
            .disabled(working)
        }
        .navigationTitle("Scanner find")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func review(approve: Bool) async {
        working = true
        let ok = await appState.perform { try await $0.reviewScanCandidate(id: candidate.id, approve: approve, reason: nil) }
        working = false
        if ok {
            appState.infoMessage = approve ? "Published to the site." : "Find rejected."
            await onResolved()
            dismiss()
        }
    }
}
