import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var appState: AppState

    var reports: [SafetyReport] {
        (appState.dashboard?.reports ?? []).sorted { lhs, rhs in
            if lhs.severity == .urgent && rhs.severity != .urgent { return true }
            if lhs.severity != .urgent && rhs.severity == .urgent { return false }
            return (lhs.createdAt ?? "") > (rhs.createdAt ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if reports.isEmpty {
                    EmptyStateRow(
                        title: "No open safety reports",
                        message: "Urgent privacy and safety issues will appear here.",
                        systemImage: "checkmark.shield"
                    )
                } else {
                    Section("Open reports") {
                        ForEach(reports) { report in
                            NavigationLink {
                                ReportDetailView(report: report)
                            } label: {
                                ReportRow(report: report)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshDashboard() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .refreshable { await appState.refreshDashboard() }
        }
    }
}

struct ReportRow: View {
    let report: SafetyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.severity == .urgent ? "Urgent" : "Normal")
                    .font(.caption.bold())
                    .foregroundStyle(report.severity == .urgent ? .red : .secondary)
                Text(report.targetType.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(report.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(report.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.headline)
            Text(report.details?.isEmpty == false ? report.details! : report.snapshotSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct ReportDetailView: View {
    @EnvironmentObject private var appState: AppState
    let report: SafetyReport
    @State private var resolutionNote = ""
    @State private var detail: AdminReportDetailResponse?
    @State private var detailError: String?

    private var currentReport: SafetyReport { detail?.report ?? report }
    private var targetPost: AdminPostDetail? { detail?.targetPost }
    private var reporter: AdminProfileSummary? { detail?.reporter }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(currentReport.severity == .urgent ? "Urgent" : "Normal")
                            .font(.caption.bold())
                            .foregroundStyle(currentReport.severity == .urgent ? .red : .secondary)
                        Spacer()
                        Text(currentReport.status.rawValue.capitalized)
                            .font(.caption.bold())
                    }
                    Text(currentReport.reason.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.title3.bold())
                    Text(currentReport.details?.isEmpty == false ? currentReport.details! : "No details provided.")
                        .font(.body)
                }
            }

            if let detailError {
                Section {
                    Label(detailError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Showing the report snapshot. Pull to refresh to load full context.")
                }
            }

            Section {
                LabeledContent("Type", value: currentReport.targetType.capitalized)
                LabeledContent("Target ID", value: String(currentReport.targetId.prefix(8)))
                if let targetPost {
                    NavigationLink {
                        AdminPostLookupDetailView(postId: targetPost.id, initialPost: targetPost)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open reported post")
                            Text(targetPost.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else if currentReport.targetType == "post" {
                    NavigationLink {
                        AdminPostLookupDetailView(postId: currentReport.targetId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open reported post")
                            Text(currentReport.snapshotTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                LabeledContent("Snapshot title", value: currentReport.snapshotTitle)
                if let description = currentReport.snapshot?.post?.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Reported target")
            } footer: {
                Text("The snapshot is what was reported. Open the post to review the current post and photos.")
            }

            Section("Reporter") {
                if let reporter {
                    LabeledContent("Name", value: reporter.displayName)
                    LabeledContent("Role", value: reporter.role?.label ?? "Member")
                    if let postalCode = reporter.postalCode, !postalCode.isEmpty {
                        LabeledContent("Postal code", value: postalCode)
                    }
                } else if let reporterId = currentReport.reporterId {
                    LabeledContent("Reporter ID", value: String(reporterId.prefix(8)))
                } else {
                    Text("Reporter information is not available.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Decision note") {
                TextField("Optional note for audit history", text: $resolutionNote, axis: .vertical)
                    .lineLimit(3...5)
            }

            Section {
                Button {
                    Task { await appState.resolve(report: currentReport, decision: "keep_visible", reason: resolutionNote) }
                } label: {
                    Label(currentReport.targetType == "post" ? "No issue - keep post visible" : "No issue - close report", systemImage: "checkmark.shield")
                }
                if currentReport.targetType == "post" {
                    Button(role: .destructive) {
                        Task { await appState.resolve(report: currentReport, decision: "hide_post", reason: resolutionNote) }
                    } label: {
                        Label("Issue found - hide reported post", systemImage: "eye.slash")
                    }
                }
                Button {
                    Task { await appState.resolve(report: currentReport, decision: "keep_open", reason: resolutionNote) }
                } label: {
                    Label("Escalate - no post change", systemImage: "hourglass")
                }
            } footer: {
                Text("Escalating changes the report status to reviewing, keeps it in the reports queue, and does not change the reported post.")
            }
        }
        .navigationTitle("Report")
        .task { await loadDetail() }
        .refreshable { await loadDetail() }
    }

    private func loadDetail() async {
        do {
            detail = try await appState.fetchReportDetail(id: report.id)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }
}

struct AdminPostLookupDetailView: View {
    @EnvironmentObject private var appState: AppState
    let postId: String
    var initialPost: AdminPostDetail?
    @State private var post: AdminPostDetail?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let displayPost = post ?? initialPost {
                AdminPostReadOnlyContent(post: displayPost)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Post unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView("Loading post...")
            }
        }
        .navigationTitle("Reported Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPost() }
        .refreshable { await loadPost() }
    }

    private func loadPost() async {
        do {
            post = try await appState.fetchPostDetail(id: postId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminPostReadOnlyContent: View {
    let post: AdminPostDetail

    var body: some View {
        List {
            Section("Post") {
                LabeledContent("Title", value: post.title)
                LabeledContent("Type", value: post.typeLabel)
                LabeledContent("Status", value: post.status.label)
                LabeledContent("Category", value: formatCategory(post.category))
                LabeledContent("Area", value: post.pickupArea)
                Text(post.description)
            }

            Section("Submitted by") {
                LabeledContent("Name", value: post.owner.displayName)
                if let postalCode = post.owner.postalCode, !postalCode.isEmpty {
                    LabeledContent("Postal code", value: postalCode)
                }
            }

            Section("Photos") {
                if post.photos.isEmpty {
                    Text("No photos attached.")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        PhotoGalleryView(title: post.title, photos: post.photos)
                    } label: {
                        Label("Review \(post.photos.count) photo\(post.photos.count == 1 ? "" : "s")", systemImage: "photo.on.rectangle")
                    }
                }
            }
        }
    }
}

private extension SafetyReport {
    var snapshotSummary: String {
        if let title = snapshot?.post?.title, !title.isEmpty {
            return title
        }
        if let description = snapshot?.post?.description, !description.isEmpty {
            return description
        }
        if let body = snapshot?.message?.body, !body.isEmpty {
            return body
        }
        return "No snapshot available."
    }

    var snapshotTitle: String {
        if let title = snapshot?.post?.title, !title.isEmpty {
            return title
        }
        if let body = snapshot?.message?.body, !body.isEmpty {
            return body
        }
        return "No title in snapshot"
    }
}
