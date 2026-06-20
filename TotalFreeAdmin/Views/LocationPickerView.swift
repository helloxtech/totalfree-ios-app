import SwiftUI
import MapKit
import CoreLocation

struct PickedLocation {
    let coordinate: CLLocationCoordinate2D
    let area: String?
    let city: String?
}

/// Drop-a-pin location picker. Works the same on iPhone and iPad: pan the map so
/// the fixed centre pin sits on your area, then confirm. Reverse-geocodes to fill
/// the neighbourhood/city. No location permission required (display + geocode only).
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (PickedLocation) -> Void

    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var resolving = false
    @State private var query = ""
    @State private var searching = false
    @State private var searchMessage: String?

    init(initial: CLLocationCoordinate2D, onPick: @escaping (PickedLocation) -> Void) {
        self.onPick = onPick
        let region = MKCoordinateRegion(center: initial, span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
        _camera = State(initialValue: .region(region))
        _center = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .center) {
                Map(position: $camera)
                    .onMapCameraChange(frequency: .continuous) { ctx in center = ctx.region.center }
                    .ignoresSafeArea(edges: .bottom)

                // Fixed centre pin (tip points at the map centre).
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.red)
                    .shadow(radius: 3)
                    .offset(y: -16)
                    .allowsHitTesting(false)

                VStack {
                    VStack(spacing: 8) {
                        Text("Drag the map to place the pin on your neighbourhood")
                            .font(.caption)
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                        HStack(spacing: 8) {
                            TextField("Search postcode or place", text: $query)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.search)
                                .onSubmit { search() }
                            Button {
                                search()
                            } label: {
                                if searching { ProgressView() } else { Text("Search").bold() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let searchMessage {
                            Text(searchMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    Spacer()
                    VStack(spacing: 8) {
                        Text(String(format: "%.4f, %.4f", center.latitude, center.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Button { confirm() } label: {
                            HStack {
                                if resolving { ProgressView() } else { Text("Use this location").bold() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(resolving)
                    }
                    .padding()
                    .background(.thinMaterial)
                }
            }
            .navigationTitle("Pin your area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func confirm() {
        resolving = true
        let coord = center
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coord.latitude, longitude: coord.longitude)) { places, _ in
            let p = places?.first
            onPick(PickedLocation(
                coordinate: coord,
                area: p?.subLocality ?? p?.locality,
                city: p?.locality ?? p?.administrativeArea
            ))
            resolving = false
            dismiss()
        }
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searching = true
        searchMessage = nil
        CLGeocoder().geocodeAddressString(term) { places, error in
            searching = false
            guard error == nil, let coord = places?.first?.location?.coordinate else {
                searchMessage = "No match found. Try a nearby street, city, or postcode."
                return
            }
            center = coord
            camera = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
            searchMessage = "Found. Adjust the map if needed, then use this location."
        }
    }
}
