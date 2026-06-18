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
                if showMap {
                    BrowseMapView(query: query, category: category, sourceType: sourceType, kind: kind, selection: $mapSelection)
                } else if loading && listings.isEmpty {
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

/// Map of free items by area. Loads pins for the visible region (not the
/// paginated list), with a "Search this area" button when the map moves — so we
/// only fetch what's on screen. Neighbour ("totalfree") pins are deterministically
/// jittered (~200m) for privacy; organization/business pins are exact.
private struct BrowseMapView: View {
    @EnvironmentObject private var appState: AppState
    let query: String
    let category: String
    let sourceType: String
    let kind: String
    @Binding var selection: Listing?

    @StateObject private var location = LocationProvider()
    @State private var pins: [Listing] = []
    @State private var region = BrowseMapView.defaultRegion
    @State private var didInitialSearch = false
    @State private var showSearchArea = false
    @State private var loading = false

    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 49.22, longitude: -122.95),   // Metro Vancouver
        span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.9)
    )

    var body: some View {
        Map(initialPosition: .region(BrowseMapView.defaultRegion)) {
            UserAnnotation()
            ForEach(pins) { listing in
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
        .onMapCameraChange(frequency: .onEnd) { ctx in
            region = ctx.region
            if !didInitialSearch {
                didInitialSearch = true
                Task { await searchArea(ctx.region) }
            } else {
                showSearchArea = true   // user moved the map → offer a re-search
            }
        }
        // Discrete filters re-search the visible area immediately; a typed query
        // just surfaces the button (so we don't fire a request per keystroke).
        .onChange(of: category) { _, _ in if didInitialSearch { Task { await searchArea(region) } } }
        .onChange(of: sourceType) { _, _ in if didInitialSearch { Task { await searchArea(region) } } }
        .onChange(of: kind) { _, _ in if didInitialSearch { Task { await searchArea(region) } } }
        .onChange(of: query) { _, _ in if didInitialSearch { showSearchArea = true } }
        .overlay(alignment: .top) {
            if showSearchArea {
                Button { Task { await searchArea(region) } } label: {
                    Label(loading ? "Searching…" : "Search this area", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(.separator)))
                        .shadow(radius: 3)
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .padding(.top, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if didInitialSearch && !loading && pins.isEmpty {
                Text("No free items in this area — try moving the map.")
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private func searchArea(_ region: MKCoordinateRegion) async {
        loading = true
        showSearchArea = false
        defer { loading = false }
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        let result = await appState.load {
            try await $0.searchListingsInBounds(
                minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
                text: query, category: category, sourceType: sourceType, kind: kind, limit: 300
            )
        }
        if let result { pins = result }
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
