import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    /// True when shown as a sheet from the bell, so we offer a Done button.
    var presentedModally = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.alertNotifications.isEmpty {
                    EmptyState(
                        title: appState.t("alerts.emptyTitle"),
                        message: appState.t("alerts.emptyMessage"),
                        systemImage: "bell"
                    )
                } else {
                    List {
                        ForEach(appState.alertNotifications) { note in
                            NavigationLink {
                                NotificationDetailView(note: note)
                            } label: {
                                row(note)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await appState.deleteNotification(note.id) }
                                } label: {
                                    Label(appState.t("alerts.delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(appState.t("alerts.title"))
            .toolbar {
                if presentedModally {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(appState.t("alerts.done")) { dismiss() }
                    }
                }
                if appState.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(appState.t("alerts.markAll")) { Task { await appState.markAllAlertsRead() } }
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
                Text(note.localizedTitle(locale: appState.preferredLocale))
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

/// Top-bar bell that opens the Alerts feed and shows an unread badge. Replaces
/// the old Alerts tab — alerts now live in the home header (like the web app).
struct NotificationBellButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAlerts = false

    var body: some View {
        Button { showAlerts = true } label: {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if appState.unreadCount > 0 {
                        Text(appState.unreadCount > 9 ? "9+" : "\(appState.unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.red, in: Capsule())
                            .offset(x: 8, y: -7)
                    }
                }
        }
        .accessibilityLabel(appState.unreadCount > 0 ? "\(appState.t("alerts.title")), \(appState.unreadCount)" : appState.t("alerts.title"))
        .sheet(isPresented: $showAlerts) {
            NotificationsView(presentedModally: true)
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
                        Text(note.localizedTitle(locale: appState.preferredLocale)).font(.headline)
                        if let body = note.body, !body.isEmpty { Text(body).font(.subheadline) }
                        Text(relativeDate(note.createdAt)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if note.type == "admin_report_new" {
                Section {
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Label(appState.t("alerts.openReports"), systemImage: "flag")
                    }
                }
            } else if note.type == "admin_listing_pending" {
                Section {
                    NavigationLink {
                        ModerationView()
                    } label: {
                        Label(appState.t("alerts.openQueue"), systemImage: "rectangle.stack.badge.person.crop")
                    }
                }
            } else if note.type == "admin_business_pending" {
                Section {
                    NavigationLink {
                        SponsorsView()
                    } label: {
                        Label(appState.t("alerts.openBusiness"), systemImage: "building.2")
                    }
                }
            } else if note.type == "admin_org_claim_pending" {
                Section {
                    NavigationLink {
                        ClaimsView()
                    } label: {
                        Label(appState.t("alerts.openClaims"), systemImage: "checkmark.seal")
                    }
                }
            }

            if let lid = note.targetListingId {
                Section {
                    NavigationLink {
                        ListingLoaderView(listingId: lid)
                    } label: {
                        Label(appState.t("alerts.viewListing"), systemImage: "shippingbox")
                    }
                }
            } else if let rid = note.targetRequestId {
                Section {
                    NavigationLink {
                        RequestLoaderView(requestId: rid)
                    } label: {
                        Label(appState.t("alerts.openConversation"), systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
        }
        .navigationTitle(appState.t("alerts.detailTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !note.read { await appState.markNotificationRead(note.id) }
        }
    }
}
