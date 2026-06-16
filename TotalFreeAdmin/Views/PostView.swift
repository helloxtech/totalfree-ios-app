import SwiftUI
import PhotosUI
import CoreLocation
import UIKit

/// Post a free item or a "wanted". Any signed-in member can post; listings go to
/// the moderation queue (status `pending_review`) before they appear publicly.
/// Supports multiple photos (Supabase Storage) and a map-pinned location.
struct PostView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var asSheet: Bool = false

    @State private var kind = "offer"
    @State private var title = ""
    @State private var description = ""
    @State private var category = "home"
    @State private var condition = "good"
    @State private var quantity = 1
    @State private var neededBy = Date()
    @State private var hasNeededBy = false
    @State private var city = ""
    @State private var area = ""

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var imagesData: [Data] = []
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var showMap = false
    @State private var submitting = false

    private let metroVancouver = CLLocationCoordinate2D(latitude: 49.22, longitude: -122.95)
    private let maxPhotos = 5

    var body: some View {
        NavigationStack {
            if appState.isAuthed {
                form
            } else {
                SignInPrompt(
                    title: "Share something free",
                    message: "Sign in or join to post a free item or ask for something you need.",
                    systemImage: "plus.circle"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Post")
            }
        }
    }

    private var form: some View {
        Form {
            if !appState.isVerified {
                Section {
                    InfoCallout(
                        title: "Confirm your email to post",
                        message: "Check your inbox for a confirmation link. You can fill this out now; posting unlocks once you're verified.",
                        systemImage: "envelope.badge"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Type", selection: $kind) {
                    Text("Free to give").tag("offer")
                    Text("Wanted").tag("wanted")
                }
                .pickerStyle(.segmented)
            }

            Section {
                photoRow
            } header: {
                Text("Photos")
            } footer: {
                Text("Add up to \(maxPhotos). The first is the cover image.")
            }

            Section("Details") {
                TextField(kind == "wanted" ? "What are you looking for?" : "What are you giving away?", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...8)
                Picker("Category", selection: $category) {
                    ForEach(AppConstants.categories, id: \.self) { c in
                        Text("\(AppConstants.categoryEmoji[c] ?? "")  \(AppConstants.categoryLabel(c))").tag(c)
                    }
                }
            }

            if kind == "offer" {
                Section("Item") {
                    Picker("Condition", selection: $condition) {
                        ForEach(AppConstants.conditions, id: \.self) { c in
                            Text(AppConstants.conditionLabels[c] ?? c).tag(c)
                        }
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }
            } else {
                Section("Timing") {
                    Toggle("Needed by a date", isOn: $hasNeededBy)
                    if hasNeededBy {
                        DatePicker("Needed by", selection: $neededBy, displayedComponents: .date)
                    }
                }
            }

            Section {
                TextField("Neighbourhood / area (e.g. White Rock)", text: $area)
                TextField("City (e.g. Surrey)", text: $city)
                Button {
                    showMap = true
                } label: {
                    Label(coordinate == nil ? "Pin location on map" : "Pinned — tap to adjust", systemImage: "mappin.and.ellipse")
                }
                if let coordinate {
                    HStack {
                        Text(String(format: "📍 %.4f, %.4f", coordinate.latitude, coordinate.longitude))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { self.coordinate = nil }.font(.caption)
                    }
                }
            } header: {
                Text("Where")
            } footer: {
                Text("Keep it to a neighbourhood or city — never a full street address in a public post.")
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if submitting { ProgressView() } else { Text("Post").bold() }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || submitting)
            }
        }
        .navigationTitle(kind == "wanted" ? "Post a wanted" : "Post a free item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .sheet(isPresented: $showMap) {
            LocationPickerView(initial: coordinate ?? metroVancouver) { picked in
                coordinate = picked.coordinate
                if area.trimmingCharacters(in: .whitespaces).isEmpty, let a = picked.area { area = a }
                if city.trimmingCharacters(in: .whitespaces).isEmpty, let c = picked.city { city = c }
            }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    @ViewBuilder
    private var photoRow: some View {
        if !imagesData.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(imagesData.enumerated()), id: \.offset) { idx, data in
                        if let ui = UIImage(data: data) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: ui).resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                if idx == 0 {
                                    Text("Cover").font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                                        .padding(3)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        PhotosPicker(selection: $photoItems, maxSelectionCount: maxPhotos, matching: .images) {
            Label(imagesData.isEmpty ? "Add photos" : "Change photos (\(imagesData.count))", systemImage: "photo.on.rectangle.angled")
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var datas: [Data] = []
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            if let ui = UIImage(data: raw) {
                datas.append(ui.jpegResized(maxDimension: 1600, quality: 0.8) ?? raw)
            } else {
                datas.append(raw)
            }
        }
        imagesData = datas
    }

    private func submit() {
        guard let uid = appState.userId else { return }
        submitting = true
        let neededByString: String? = {
            guard kind == "wanted", hasNeededBy else { return nil }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: neededBy)
        }()
        Task {
            var urls: [String] = []
            for data in imagesData {
                if let u = await appState.load({ try await $0.uploadImage(data, contentType: "image/jpeg", ext: "jpg", userId: uid) }) {
                    urls.append(u)
                } else {
                    submitting = false
                    return // an upload failed; error already surfaced
                }
            }
            let ok = await appState.perform {
                _ = try await $0.createListing(
                    ownerId: uid,
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    category: category,
                    kind: kind,
                    condition: condition,
                    quantity: quantity,
                    neededBy: neededByString,
                    city: city.trimmingCharacters(in: .whitespaces),
                    area: area.trimmingCharacters(in: .whitespaces),
                    imageUrls: urls,
                    lat: coordinate?.latitude,
                    lng: coordinate?.longitude
                )
            }
            submitting = false
            if ok {
                appState.infoMessage = "Posted! It'll appear once a moderator approves it."
                if asSheet { dismiss() } else { reset() }
            }
        }
    }

    private func reset() {
        title = ""; description = ""; quantity = 1
        hasNeededBy = false; city = ""; area = ""
        imagesData = []; photoItems = []; coordinate = nil
    }
}

extension UIImage {
    /// Returns JPEG data scaled so the longest side is <= maxDimension.
    func jpegResized(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let scaled = renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
        return scaled.jpegData(compressionQuality: quality)
    }
}
