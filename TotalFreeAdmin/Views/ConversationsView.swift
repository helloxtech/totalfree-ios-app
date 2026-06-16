import SwiftUI

/// Read any conversation (every request thread). Gated by message.read.any; RLS
/// lets staff read all requests/messages but not send (the thread opens read-only).
struct ConversationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var requests: [AppRequest] = []
    @State private var loading = false

    var body: some View {
        Group {
            if loading && requests.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if requests.isEmpty {
                EmptyState(title: "No conversations", message: "No requests have started yet.", systemImage: "bubble.left.and.bubble.right")
            } else {
                List(requests) { req in
                    NavigationLink {
                        RequestThreadView(request: req, readOnly: true)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(req.itemTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Spacer()
                                StatusBadge(status: req.status)
                            }
                            if !req.message.isEmpty {
                                Text(req.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Text("Updated \(relativeDate(req.updatedAt ?? req.createdAt))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchAllRequests() }) { requests = r }
    }
}
