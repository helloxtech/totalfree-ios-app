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
    let asSheet: Bool

    @State private var kind: String
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

    init(initialKind: String = "offer", asSheet: Bool = false) {
        self.asSheet = asSheet
        _kind = State(initialValue: initialKind == "wanted" ? "wanted" : "offer")
    }

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
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var form: some View {
        Form {
            if !appState.isVerified {
                Section {
                    InfoCallout(
                        title: "Confirm your email to post",
                        message: "Check your inbox for a confirmation link. Posting unlocks once you're verified.",
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
                if let submitHint {
                    Text(submitHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(kind == "wanted" ? "Post a wanted" : "Post a free item")
        .navigationBarTitleDisplayMode(.inline)
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
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 82, height: 82)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(idx == 0 ? "Cover" : "\(idx + 1)")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(idx == 0 ? Theme.accent : Color(.systemBackground), in: Capsule())
                                        .foregroundStyle(idx == 0 ? .white : .secondary)
                                        .padding(4)
                                }
                                HStack(spacing: 4) {
                                    if idx != 0 {
                                        Button("Cover") { makeCover(idx) }
                                            .font(.caption2.bold())
                                            .buttonStyle(.bordered)
                                    }
                                    Button(role: .destructive) { removePhoto(idx) } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.bold())
                                    }
                                    .buttonStyle(.bordered)
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
        let hasTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        let hasDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
        let hasPlace = coordinate != nil ||
            !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return appState.isVerified && hasTitle && hasDescription && hasPlace
    }

    private var submitHint: String? {
        if !appState.isVerified { return "Confirm your email before posting." }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 { return "Add a clear title." }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 { return "Add a sentence or two of detail." }
        let hasPlace = coordinate != nil ||
            !area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasPlace { return "Add a neighbourhood, city, or map pin." }
        return nil
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

    private func removePhoto(_ index: Int) {
        guard imagesData.indices.contains(index) else { return }
        imagesData.remove(at: index)
        if photoItems.indices.contains(index) {
            photoItems.remove(at: index)
        } else if imagesData.isEmpty {
            photoItems = []
        }
    }

    private func makeCover(_ index: Int) {
        guard imagesData.indices.contains(index) else { return }
        let data = imagesData.remove(at: index)
        imagesData.insert(data, at: 0)
        if photoItems.indices.contains(index) {
            let item = photoItems.remove(at: index)
            photoItems.insert(item, at: 0)
        }
    }

    private func submit() {
        guard let uid = appState.userId else { return }
        guard appState.isVerified else {
            appState.infoMessage = "Please confirm your email before posting."
            return
        }
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
                appState.infoMessage = "Posted. Low-risk posts go live right away; others appear after review."
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
