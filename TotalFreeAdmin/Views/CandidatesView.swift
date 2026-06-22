import SwiftUI

/// Scanner finds awaiting review (`listing_candidates`, status needs_review).
/// Tap a row for the full find; swipe to approve/reject. Gated by listing.review.
struct CandidatesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var candidates: [ScanCandidate] = []
    @State private var today: ScannerToday?
    @State private var loading = false

    var body: some View {
        Group {
            if loading && candidates.isEmpty && today == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let t = today {
                        Section("Today's scanner report") {
                            todaySummary(t)
                        }
                    }
                    Section("Waiting for review (\(candidates.count))") {
                        if candidates.isEmpty {
                            Text("Nothing queued for review right now.").font(.caption).foregroundStyle(.secondary)
                        } else {
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
                    }
                }
            }
        }
        .navigationTitle("Scanner finds")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    // Current-day report (item 4): compact counts + the day's finds.
    private func todaySummary(_ t: ScannerToday) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                todayStat("Found", t.found)
                todayStat("Published", t.published)
                todayStat("Rejected", t.rejected)
                todayStat("Waiting", t.pendingNow)
            }
            if let items = t.items, !items.isEmpty {
                ForEach(items.prefix(6)) { it in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.title).font(.caption.weight(.semibold)).lineLimit(1)
                            Text([it.agent?.capitalized, it.city, it.sourceDomain].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        todayStatusTag(it.status)
                    }
                }
            } else {
                Text("No finds yet today.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func todayStat(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 2) {
            Text("\(value ?? 0)").font(.headline).foregroundStyle(Theme.accent)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func todayStatusTag(_ status: String) -> some View {
        let info: (String, Color)
        switch status {
        case "published": info = ("published", .green)
        case "needs_review": info = ("waiting", .orange)
        case "duplicate": info = ("duplicate", .gray)
        default: info = (status, .red)
        }
        return Text(info.0)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(info.1.opacity(0.18), in: Capsule())
            .foregroundStyle(info.1)
    }

    private func summary(_ c: ScanCandidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(subtitle(for: c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                confidenceBadge(c)
            }
            if let quote = c.evidenceQuote, !quote.isEmpty {
                Text(quote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private func subtitle(for c: ScanCandidate) -> String {
        let category = c.payload?.category.map(AppConstants.categoryLabel)
        return [
            category,
            [c.payload?.area, c.payload?.city].compactMap { $0 }.first,
            c.sourceDomain,
            c.createdAt.map(relativeDate),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func confidenceBadge(_ c: ScanCandidate) -> some View {
        Text(c.confidencePct ?? "Check")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor(c).opacity(0.15), in: Capsule())
            .foregroundStyle(confidenceColor(c))
    }

    private func confidenceColor(_ c: ScanCandidate) -> Color {
        guard let value = c.confidence else { return .orange }
        if value >= 0.85 { return .green }
        if value >= 0.65 { return .orange }
        return .red
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        today = await appState.load({ try await $0.fetchScannerToday() })
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(candidate.title).font(.title3.weight(.semibold))
                    HStack {
                        if let pct = candidate.confidencePct {
                            Label(pct, systemImage: "gauge.with.dots.needle.bottom.50percent")
                        } else {
                            Label("Manual check", systemImage: "exclamationmark.magnifyingglass")
                        }
                        Spacer()
                        StatusBadge(status: candidate.status)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 4)
            }
            if let p = candidate.payload {
                Section("What will be published") {
                    CandidateFactRow("Category", value: p.category.map(AppConstants.categoryLabel) ?? "Not provided", systemImage: "tag")
                    CandidateFactRow("Area", value: [p.area, p.city].compactMap { $0 }.first ?? "Not provided", systemImage: "mappin")
                    CandidateFactRow("Source", value: candidate.sourceDomain ?? "Unknown", systemImage: "link")
                    if let agent = candidate.agent {
                        CandidateFactRow("Scanner", value: agent, systemImage: "cpu")
                    }
                    if let created = candidate.createdAt {
                        CandidateFactRow("Queued", value: relativeDate(created), systemImage: "clock")
                    }
                    if let desc = p.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(desc).font(.subheadline).lineLimit(6)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if let q = candidate.evidenceQuote, !q.isEmpty {
                Section("Evidence") {
                    Text(q)
                        .font(.subheadline)
                        .italic()
                        .textSelection(.enabled)
                }
            }
            if let link = candidate.payload?.link, let u = URL(string: link) {
                Section {
                    Link(destination: u) {
                        Label("Open source page", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Approve only if the source clearly says the offer is free, public, and still available.")
                }
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

private struct CandidateFactRow: View {
    let label: String
    let value: String
    let systemImage: String

    init(_ label: String, value: String, systemImage: String) {
        self.label = label
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline).textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
