import SwiftUI
import UIKit

struct QueueView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedTab: AdminTab
    @State private var showPendingList = false

    var posts: [PendingPost] {
        appState.dashboard?.pendingPosts ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if let stats = appState.dashboard?.stats {
                    MetricsStrip(
                        stats: stats,
                        onPending: { showPendingList = true },
                        onReports: { selectedTab = .reports },
                        onMembers: appState.role.canManageAccess ? { selectedTab = .members } : nil,
                        onActive: appState.role.canManageAccess ? { selectedTab = .statistics } : nil
                    )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if posts.isEmpty {
                    EmptyStateRow(
                        title: "No posts waiting",
                        message: "New submissions will appear here first.",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    Section("Pending posts") {
                        ForEach(posts) { post in
                            NavigationLink {
                                PostReviewDetailView(post: post)
                            } label: {
                                PendingPostRow(post: post)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshDashboard() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await appState.refreshDashboard()
            }
            .navigationDestination(isPresented: $showPendingList) {
                PendingPostsListView(posts: posts)
            }
        }
    }
}

struct PendingPostsListView: View {
    let posts: [PendingPost]

    var body: some View {
        List {
            if posts.isEmpty {
                EmptyStateRow(
                    title: "No posts waiting",
                    message: "New submissions will appear here first.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ForEach(posts) { post in
                    NavigationLink {
                        PostReviewDetailView(post: post)
                    } label: {
                        PendingPostRow(post: post)
                    }
                }
            }
        }
        .navigationTitle("Pending posts")
    }
}

struct PendingPostRow: View {
    let post: PendingPost

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailPlaceholder(photoCount: post.photos.count, kind: post.postType)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(post.typeLabel)
                        .font(.caption.bold())
                        .foregroundStyle(post.postType == "request" ? .blue : .green)
                    Text(formatCategory(post.category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(post.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(post.pickupArea) · \(post.owner.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(post.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PostReviewDetailView: View {
    @EnvironmentObject private var appState: AppState
    let post: PendingPost
    @State private var showReject = false
    @State private var rejectReason = ""
    @State private var detail: AdminPostDetail?
    @State private var detailError: String?
    @State private var addressChecked = false
    @State private var freeOnlyChecked = false
    @State private var photosChecked = false

    private var displayTitle: String { detail?.title ?? post.title }
    private var displayDescription: String { detail?.description ?? post.description }
    private var displayPickupArea: String { detail?.pickupArea ?? post.pickupArea }
    private var displayOwner: String { detail?.owner.displayName ?? post.owner.displayName }
    private var displayCategory: String { formatCategory(detail?.category ?? post.category) }
    private var photos: [PostPhoto] { detail?.photos ?? post.photos }
    private var checklistComplete: Bool { addressChecked && freeOnlyChecked && photosChecked }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(post.typeLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(post.postType == "request" ? Color.blue.opacity(0.12) : Color.green.opacity(0.12), in: Capsule())
                        Spacer()
                        Text(detail?.status.label ?? "Pending review")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Text(displayTitle)
                        .font(.title2.bold())
                    Text(displayDescription)
                        .font(.body)
                    LabeledContent("Category", value: displayCategory)
                        .font(.subheadline)
                    Label(displayPickupArea, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("Submitted by \(displayOwner)", systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let detail, let availability = detail.availabilityWindow, !availability.isEmpty {
                        Label(availability, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let detail, let safetyNote = detail.safetyNote, !safetyNote.isEmpty {
                        Text(safetyNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            if let detailError {
                Section {
                    Label(detailError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Showing the queue snapshot. Pull to refresh or try again later.")
                }
            }

            Section("Photos") {
                if photos.isEmpty {
                    Text("No photos attached.")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        PhotoGalleryView(title: displayTitle, photos: photos)
                    } label: {
                        Label("Review \(photos.count) photo\(photos.count == 1 ? "" : "s")", systemImage: "photo.on.rectangle")
                    }
                }
            }

            Section {
                ChecklistItem("No exact address, phone, email, or school ID", isChecked: $addressChecked)
                ChecklistItem("Free item only: no payment, trade, tip, service, ride, or childcare", isChecked: $freeOnlyChecked)
                ChecklistItem("Photos do not show faces, mail, license plates, or private documents", isChecked: $photosChecked)
            } header: {
                Text("Moderator checklist")
            } footer: {
                Text("Approve only after every safety check is complete.")
            }

            Section {
                Button {
                    Task { await appState.approvePost(id: post.id) }
                } label: {
                    Label("Approve post", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!checklistComplete)

                Button(role: .destructive) {
                    showReject = true
                } label: {
                    Label("Reject with reason", systemImage: "xmark.octagon")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Review")
        .task {
            await loadDetail()
        }
        .refreshable {
            await loadDetail()
        }
        .sheet(isPresented: $showReject) {
            RejectPostSheet(postId: post.id, postTitle: displayTitle, reason: $rejectReason)
        }
    }

    private func loadDetail() async {
        do {
            detail = try await appState.fetchPostDetail(id: post.id)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }
}

struct RejectPostSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let postId: String
    let postTitle: String
    @Binding var reason: String

    private let templates = [
        "Please remove personal contact details.",
        "Please remove the exact pickup address.",
        "This looks like payment, trade, service, or donation.",
        "The photo may show private information.",
        "Please clarify the item condition."
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Post") {
                    Text(postTitle)
                }
                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 120)
                }
                Section("Templates") {
                    ForEach(templates, id: \.self) { template in
                        Button(template) { reason = template }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        Task {
                            await appState.rejectPost(id: postId, reason: reason)
                            dismiss()
                        }
                    } label: {
                        Label("Reject post", systemImage: "xmark.octagon")
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                } footer: {
                    Text("The member can edit and submit again.")
                }
            }
            .navigationTitle("Reject post")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct PhotoGalleryView: View {
    let title: String
    let photos: [PostPhoto]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                ForEach(photos) { photo in
                    AuthenticatedPhotoView(photo: photo)
                }
            }
            .padding()
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Photos")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct AuthenticatedPhotoView: View {
    @EnvironmentObject private var appState: AppState
    let photo: PostPhoto
    @State private var image: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(minHeight: 260)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if let errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                } else {
                    ProgressView()
                }
            }
            Text("Photo \(photo.id.prefix(8))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: photo.id) {
            await loadPhoto()
        }
    }

    private func loadPhoto() async {
        do {
            let path = photo.url ?? "/api/admin/photos/\(photo.id)"
            let data = try await appState.client.data(path)
            image = UIImage(data: data)
            if image == nil {
                errorMessage = "Could not read this image."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
