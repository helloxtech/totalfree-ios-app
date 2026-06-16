import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.notifications.isEmpty {
                    EmptyState(
                        title: "You're all caught up",
                        message: "Alerts about your requests, messages, and approved posts show up here.",
                        systemImage: "bell"
                    )
                } else {
                    List {
                        ForEach(appState.notifications) { note in
                            NavigationLink {
                                NotificationDetailView(note: note)
                            } label: {
                                row(note)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await appState.deleteNotification(note.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Alerts")
            .toolbar {
                if appState.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { Task { await appState.markAllNotificationsRead() } }
                    }
                }
            }
            .refreshable { await appState.refreshNotifications() }
            .task { await appState.refreshNotifications() }
        }
    }

    private func row(_ note: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.icon)
                .foregroundStyle(note.read ? .secondary : Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.subheadline.weight(note.read ? .regular : .semibold))
                if let body = note.body, !body.isEmpty {
                    Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(relativeDate(note.createdAt)).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !note.read {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
            }
        }
    }
}

/// Opens an alert: shows its content, marks it read, and deep-links to the
/// related listing or conversation when the notification carries an id.
struct NotificationDetailView: View {
    @EnvironmentObject private var appState: AppState
    let note: AppNotification

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: note.icon).font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.displayTitle).font(.headline)
                        if let body = note.body, !body.isEmpty { Text(body).font(.subheadline) }
                        Text(relativeDate(note.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let lid = note.targetListingId {
                Section {
                    NavigationLink {
                        ListingLoaderView(listingId: lid)
                    } label: {
                        Label("View listing", systemImage: "shippingbox")
                    }
                }
            } else if let rid = note.targetRequestId {
                Section {
                    NavigationLink {
                        RequestLoaderView(requestId: rid)
                    } label: {
                        Label("Open conversation", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
        }
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !note.read { await appState.markNotificationRead(note.id) }
        }
    }
}
