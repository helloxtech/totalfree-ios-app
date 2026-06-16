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
                    Text("Drag the map to place the pin on your neighbourhood")
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
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
}
