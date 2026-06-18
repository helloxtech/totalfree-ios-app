import SwiftUI
import MapKit
import CoreLocation

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
    @State private var showMap = false
    @State private var mapSelection: Listing?

    private var filtersActive: Bool { !sourceType.isEmpty || !kind.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                header
                searchAndFilter
                categoryChips
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $mapSelection) { listing in
                NavigationStack { ListingDetailView(listing: listing) }
            }
            .task { if !loaded { await reload(); loaded = true } }
            .onChange(of: category) { _, _ in Task { await reload() } }
            .onChange(of: sourceType) { _, _ in Task { await reload() } }
            .onChange(of: kind) { _, _ in Task { await reload() } }
        }
    }

    // Compact title row — the title shares the row with the alert bell to save height.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TotalFree").font(.title.bold())
            Spacer()
            if appState.isAuthed { NotificationBellButton() }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // Search field with the filter control directly to its right (easy to spot).
    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search free items, places…", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await reload() } }
                if !query.isEmpty {
                    Button { query = ""; Task { await reload() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 11))

            Menu {
                Picker("Kind", selection: $kind) {
                    Text("Offers & wanted").tag("")
                    Text("Free to give").tag("offer")
                    Text("Wanted").tag("wanted")
                }
                Picker("Source", selection: $sourceType) {
                    Text("Everyone").tag("")
                    ForEach(AppConstants.sourceBuckets) { b in Text(b.label).tag(b.id) }
                }
            } label: {
                Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .frame(width: 44, height: 42)
                    .background(filtersActive ? Theme.accent.opacity(0.15) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(filtersActive ? Theme.accent : .primary)
            }
            .accessibilityLabel("Filters")
        }
        .padding(.horizontal)
    }

    private var categoryChips: some View {
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
        }
    }

    @ViewBuilder
    private var content: some View {
        // In map mode the toggle moves to the top-LEFT so it never sits under the
        // map's location button (which lives top-right); in list mode it stays right.
        ZStack(alignment: showMap ? .topLeading : .topTrailing) {
            Group {
                if loading && listings.isEmpty {
                    ProgressView("Finding free things…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if showMap {
                    BrowseMapView(listings: listings, selection: $mapSelection)
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
                    .refreshable { await reload() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            viewToggle
                .padding(showMap ? .leading : .trailing, 14)
                .padding(.top, 8)
        }
    }

    // Floating List/Map toggle — labelled with the mode you'd switch TO, so it
    // costs no vertical space the way a full segmented row did.
    private var viewToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showMap.toggle() }
        } label: {
            Label(showMap ? "List" : "Map", systemImage: showMap ? "list.bullet" : "map.fill")
                .font(.caption.bold())
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(Theme.accent)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(.separator)))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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

/// Minimal Core Location helper — just asks for When-In-Use authorization so the
/// map's user-location button and blue dot light up. The Map itself tracks the
/// position; we don't need to consume individual fixes.
@MainActor
final class LocationProvider: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    func requestWhenInUse() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

/// Map of the current browse results. Pins for neighbour ("totalfree") posts are
/// deterministically jittered (~200m) so a private home is never pinpointed;
/// organization/business listings keep their exact location.
private struct BrowseMapView: View {
    let listings: [Listing]
    @Binding var selection: Listing?
    @StateObject private var location = LocationProvider()

    private var mappable: [Listing] { listings.filter { $0.lat != nil && $0.lng != nil } }

    var body: some View {
        if mappable.isEmpty {
            EmptyState(
                title: "No map pins here",
                message: "These results don't have map locations yet. Switch back to List to see them.",
                systemImage: "mappin.slash"
            )
        } else {
            Map(initialPosition: .automatic) {
                UserAnnotation()
                ForEach(mappable) { listing in
                    Annotation(listing.title, coordinate: coordinate(for: listing)) {
                        Button { selection = listing } label: { pin(for: listing) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()   // the "locate me" button
                MapCompass()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)
            .onAppear { location.requestWhenInUse() }
            .overlay(alignment: .bottom) {
                if mappable.count < listings.count {
                    Text("\(mappable.count) of \(listings.count) results have a map location")
                        .font(.caption2)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private func pin(for listing: Listing) -> some View {
        Image(systemName: listing.isWanted ? "hand.raised.fill" : "gift.fill")
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(6)
            .background(colorForSource(listing.sourceType), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(radius: 1)
    }

    private func coordinate(for listing: Listing) -> CLLocationCoordinate2D {
        let lat = listing.lat ?? 0, lng = listing.lng ?? 0
        // Exact for organizations/businesses; jittered for neighbour posts (private homes).
        guard listing.sourceType == "totalfree" else {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        let h = stableHash(listing.id)
        let dLat = (Double(h % 400) / 400.0 - 0.5) * 0.004        // ~±220m
        let dLng = (Double((h / 400) % 400) / 400.0 - 0.5) * 0.004
        return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)
    }

    /// Stable across launches (Swift's String.hashValue is per-process randomized).
    private func stableHash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = ((h << 5) &+ h) &+ Int(b) }
        return abs(h)
    }
}
