import SwiftUI

/// Public neighbourhood feed. Works fully signed-out.
struct BrowseView: View {
    @EnvironmentObject private var appState: AppState

    @State private var listings: [Listing] = []
    @State private var query = ""
    @State private var category = ""
    @State private var sourceType = ""
    @State private var kind = ""
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && listings.isEmpty {
                    ProgressView("Finding free things…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if listings.isEmpty {
                    EmptyState(
                        title: "Nothing here yet",
                        message: "Try a different search or filter. New free items appear as neighbours post them.",
                        systemImage: "gift"
                    )
                } else {
                    List {
                        ForEach(listings) { listing in
                            NavigationLink {
                                ListingDetailView(listing: listing)
                            } label: {
                                ListingCard(listing: listing)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("TotalFree")
            .searchable(text: $query, prompt: "Search free items, places…")
            .onSubmit(of: .search) { Task { await reload() } }
            .refreshable { await reload() }
            .safeAreaInset(edge: .top) { filterBar }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Kind", selection: $kind) {
                            Text("Offers & wanted").tag("")
                            Text("Free to give").tag("offer")
                            Text("Wanted").tag("wanted")
                        }
                        Picker("Source", selection: $sourceType) {
                            Text("Everyone").tag("")
                            ForEach(AppConstants.sourceBuckets) { b in
                                Text(b.label).tag(b.id)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { if !loaded { await reload(); loaded = true } }
            .onChange(of: category) { _, _ in Task { await reload() } }
            .onChange(of: sourceType) { _, _ in Task { await reload() } }
            .onChange(of: kind) { _, _ in Task { await reload() } }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryFilterChip(label: "All", selected: category.isEmpty) { category = "" }
                ForEach(AppConstants.categories, id: \.self) { cat in
                    CategoryFilterChip(
                        label: "\(AppConstants.categoryEmoji[cat] ?? "") \(AppConstants.categoryLabel(cat))",
                        selected: category == cat
                    ) { category = category == cat ? "" : cat }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        let result = await appState.load {
            try await $0.searchListings(
                text: query, city: "", category: category,
                sourceType: sourceType, kind: kind, limit: 48
            )
        }
        if let result { listings = result }
    }
}

private struct CategoryFilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selected ? Theme.accent : Color(.secondarySystemFill),
                    in: Capsule()
                )
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
