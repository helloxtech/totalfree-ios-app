import SwiftUI

/// Staff safety-report queue. Tap a report to open the reported listing; swipe to
/// resolve. Pushed inside the Admin tab's NavigationStack.
struct ReportsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var rows: [ReportRow] = []
    @State private var loading = false

    private var openRows: [ReportRow] { rows.filter { $0.report.status == "open" } }
    private var resolvedRows: [ReportRow] { rows.filter { $0.report.status != "open" } }

    var body: some View {
        Group {
            if loading && rows.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                EmptyState(title: "No reports", message: "Nothing has been reported. The community is in good shape.", systemImage: "flag")
            } else {
                List {
                    if !openRows.isEmpty {
                        Section("Open (\(openRows.count))") {
                            ForEach(openRows) { row in
                                reportRow(row)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button { resolve(row, "removed") } label: { Label("Remove", systemImage: "trash") }.tint(.red)
                                        Button { resolve(row, "warned") } label: { Label("Warn", systemImage: "exclamationmark.triangle") }.tint(.orange)
                                        Button { resolve(row, "dismissed") } label: { Label("Dismiss", systemImage: "checkmark") }.tint(.gray)
                                    }
                            }
                        }
                    }
                    if !resolvedRows.isEmpty {
                        Section("Resolved") { ForEach(resolvedRows) { reportRow($0) } }
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    @ViewBuilder
    private func reportRow(_ row: ReportRow) -> some View {
        if row.report.targetType == "listing" {
            NavigationLink {
                ListingLoaderView(listingId: row.report.targetId)
            } label: {
                ReportRowSummary(row: row)
            }
        } else {
            ReportRowSummary(row: row)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchReports() }) { rows = r }
        await appState.refreshStaffCounts()
    }

    private func resolve(_ row: ReportRow, _ status: String) {
        Task {
            let ok = await appState.perform { try await $0.resolveReport(id: row.report.id, status: status) }
            if ok { await reload() }
        }
    }
}

private struct ReportRowSummary: View {
    let row: ReportRow
    private var r: Report { row.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(r.targetType.capitalized, systemImage: icon).font(.caption.bold())
                Spacer()
                StatusBadge(status: r.status)
            }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text("Reason: \(r.reason.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.caption).foregroundStyle(.secondary)
            if let d = r.description, !d.isEmpty {
                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Text("By \(r.reporter?.name ?? "someone") · \(relativeDate(r.createdAt))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch r.targetType {
        case "listing": "shippingbox"
        case "message": "bubble.left"
        case "request": "hands.sparkles"
        case "profile": "person"
        default: "flag"
        }
    }
    private var title: String {
        r.targetType == "listing" ? (row.listingTitle ?? "Listing") : r.targetType.capitalized
    }
}
