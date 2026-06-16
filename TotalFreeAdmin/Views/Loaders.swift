import SwiftUI

/// Loads a listing by id, then shows its detail. Used for deep-linking from
/// notifications and from reports (whose target is a bare listing id).
struct ListingLoaderView: View {
    @EnvironmentObject private var appState: AppState
    let listingId: String
    @State private var listing: Listing?
    @State private var loading = true

    var body: some View {
        Group {
            if let listing {
                ListingDetailView(listing: listing)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(title: "Not found", message: "This item may have been removed.", systemImage: "questionmark.circle")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        listing = (await appState.load { try await $0.fetchListing(id: listingId) }) ?? nil
        loading = false
    }
}

/// Loads a request by id, then shows its conversation thread.
struct RequestLoaderView: View {
    @EnvironmentObject private var appState: AppState
    let requestId: String
    var readOnly: Bool = false
    @State private var request: AppRequest?
    @State private var loading = true

    var body: some View {
        Group {
            if let request {
                RequestThreadView(request: request, readOnly: readOnly)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(title: "Not found", message: "This conversation is no longer available.", systemImage: "questionmark.circle")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        request = (await appState.load { try await $0.fetchRequest(id: requestId) }) ?? nil
        loading = false
    }
}
