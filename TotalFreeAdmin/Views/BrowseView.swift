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
    @State private var loading = false
    @State private var loaded = false
    @State private var showMap = false
    @State private var mapSelection: Listing?

    private let kind = "offer"
    private let gridColumns = [
        GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
        GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top)
    ]
    private var filtersActive: Bool { !sourceType.isEmpty || !category.isEmpty }
    private var activeFilterCount: Int { [sourceType, category].filter { !$0.isEmpty }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                header
                searchAndFilter
                activeFilterStrip
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $mapSelection) { listing in
                NavigationStack { ListingDetailView(listing: listing) }
            }
            .task { if !loaded { await reload(); loaded = true } }
            .onChange(of: category) { _, _ in Task { await reload() } }
            .onChange(of: sourceType) { _, _ in Task { await reload() } }
        }
    }

    // Compact title row — the title shares the row with the alert bell to save height.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total Free").font(.title.bold())
            Spacer()
            if appState.isAuthed { NotificationBellButton() }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // Search first, filters tucked into one control so listings appear sooner.
    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search free stuff", text: $query)
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
                Picker("Source", selection: $sourceType) {
                    Label("Everyone", systemImage: "person.3").tag("")
                    ForEach(AppConstants.sourceBuckets) { b in
                        Label(b.label, systemImage: AppConstants.sourceSymbol(b.id)).tag(b.id)
                    }
                }
                Picker("Category", selection: $category) {
                    Label("All categories", systemImage: "square.grid.2x2").tag("")
                    ForEach(AppConstants.browseCategories, id: \.self) { cat in
                        Label(AppConstants.categoryLabel(cat), systemImage: AppConstants.categorySymbol(cat)).tag(cat)
                    }
                }
                if filtersActive {
                    Button("Clear filters", role: .destructive) {
                        sourceType = ""
                        category = ""
                    }
                }
            } label: {
                Label(filtersActive ? "Filters \(activeFilterCount)" : "Filters", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 42)
                    .padding(.horizontal, 10)
                    .background(filtersActive ? Theme.accent.opacity(0.15) : Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(filtersActive ? Theme.accent : .primary)
            }
            .accessibilityLabel("Filters")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var activeFilterStrip: some View {
        if filtersActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !sourceType.isEmpty {
                        CategoryFilterChip(label: "\(AppConstants.sourceLabel(sourceType)) ×", systemImage: AppConstants.sourceSymbol(sourceType), selected: true) { sourceType = "" }
                    }
                    if !category.isEmpty {
                        CategoryFilterChip(label: "\(AppConstants.categoryLabel(category)) ×", systemImage: AppConstants.categorySymbol(category), selected: true) { category = "" }
                    }
                    CategoryFilterChip(label: "Clear", systemImage: "xmark.circle", selected: false) {
                        sourceType = ""
                        category = ""
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var resultsBar: some View {
        HStack(spacing: 12) {
            Text(listings.isEmpty ? "Free items" : "\(listings.count) free item\(listings.count == 1 ? "" : "s")")
                .font(.headline)
            Spacer()
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { showMap = false } } label: {
                    Label("List", systemImage: "square.grid.2x2")
                }
                .buttonStyle(BrowseModeButtonStyle(active: !showMap))

                Button { withAnimation(.easeInOut(duration: 0.15)) { showMap = true } } label: {
                    Label("Map", systemImage: "mappin")
                }
                .buttonStyle(BrowseModeButtonStyle(active: showMap))
            }
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 8) {
            resultsBar
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
                    ScrollView {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                            ForEach(listings) { listing in
                                NavigationLink {
                                    ListingDetailView(listing: listing)
                                } label: {
                                    BrowseListingTile(listing: listing)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 104)
                    }
                    .refreshable { await reload() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
    let systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(label)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
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

private struct BrowseModeButtonStyle: ButtonStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(active ? Color(.systemBackground) : Color.clear, in: Capsule())
            .foregroundStyle(active ? Theme.accent : .secondary)
            .shadow(color: active ? .black.opacity(0.08) : .clear, radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct BrowseListingTile: View {
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                tileMedia
                TileSourceBadge(sourceType: listing.sourceType)
                    .padding(8)
            }
            Text(listing.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppConstants.categoryLabel(listing.category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Label(listing.locationText, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if ["partner", "sponsored"].contains(listing.sourceType), !listing.sourceLabelText.isEmpty {
                    Text("by \(listing.sourceLabelText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tileMedia: some View {
        GeometryReader { proxy in
            Group {
                if let url = listing.imageUrl, let u = URL(string: url) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        case .empty:
                            ProgressView()
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.width)
            .background(colorForSource(listing.sourceType).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator).opacity(0.45)))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.title)
            Text(AppConstants.categoryLabel(listing.category))
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .foregroundStyle(colorForSource(listing.sourceType))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        switch listing.category {
        case "furniture": "chair"
        case "home": "house"
        case "school", "learning": "books.vertical"
        case "kids": "figure.2.and.child.holdinghands"
        case "sports": "soccerball"
        case "food": "cup.and.saucer"
        case "clothing": "tshirt"
        default: "gift"
        }
    }
}

private struct TileSourceBadge: View {
    let sourceType: String

    var body: some View {
        Text(AppConstants.sourceLabel(sourceType))
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(colorForSource(sourceType).opacity(0.45), lineWidth: 1))
            .foregroundStyle(colorForSource(sourceType))
            .accessibilityLabel("Source: \(AppConstants.sourceLabel(sourceType))")
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
