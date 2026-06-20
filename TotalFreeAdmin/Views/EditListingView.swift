import SwiftUI
import PhotosUI
import UIKit

/// Edit any listing's content (title / description / category / condition).
/// Gated by listing.edit.any; presented as a sheet from the moderation detail.
struct EditListingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let listing: Listing
    var resubmitOnSave: Bool = false
    var onSaved: (Listing) -> Void

    @State private var title: String
    @State private var description: String
    @State private var category: String
    @State private var condition: String
    @State private var imageUrls: [String]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var saving = false

    init(listing: Listing, resubmitOnSave: Bool = false, onSaved: @escaping (Listing) -> Void) {
        self.listing = listing
        self.resubmitOnSave = resubmitOnSave
        self.onSaved = onSaved
        _title = State(initialValue: listing.title)
        _description = State(initialValue: listing.description)
        _category = State(initialValue: listing.category)
        _condition = State(initialValue: listing.condition ?? "good")
        _imageUrls = State(initialValue: listing.galleryUrls)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(3...8)
                    Picker("Category", selection: $category) {
                        ForEach(AppConstants.categories, id: \.self) { c in
                            Text(AppConstants.categoryLabel(c)).tag(c)
                        }
                    }
                }
                if !listing.isWanted {
                    Section {
                        photoManager
                    } header: {
                        Text("Photos")
                    } footer: {
                        Text("The first photo is the cover. Add several, remove weak photos, or change the cover.")
                    }
                    Section("Condition") {
                        Picker("Condition", selection: $condition) {
                            ForEach(AppConstants.conditions, id: \.self) { c in
                                Text(AppConstants.conditionLabels[c] ?? c).tag(c)
                            }
                        }
                    }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await uploadPhotos(items) }
            }
            .navigationTitle("Edit listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            let updated = await appState.load {
                try await $0.updateListing(
                    id: listing.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    category: category,
                    condition: listing.isWanted ? nil : condition,
                    imageUrls: listing.isWanted ? nil : imageUrls,
                    resubmit: resubmitOnSave
                )
            }
            saving = false
            if let updated {
                appState.infoMessage = resubmitOnSave ? "Saved — sent back for review." : "Listing updated."
                onSaved(updated)
                dismiss()
            }
        }
    }

    private var photoManager: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !imageUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(imageUrls.enumerated()), id: \.offset) { idx, url in
                            VStack(spacing: 5) {
                                AsyncImage(url: URL(string: url)) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFill()
                                    } else if phase.error != nil {
                                        Image(systemName: "photo").foregroundStyle(.secondary)
                                    } else {
                                        ProgressView()
                                    }
                                }
                                .frame(width: 82, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
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
                                        Image(systemName: "xmark").font(.caption2.bold())
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                Label(uploading ? "Uploading..." : "Add photos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(uploading || imageUrls.count >= 8)
            if !imageUrls.isEmpty {
                Button("Remove all photos", role: .destructive) { imageUrls = [] }
                    .font(.caption)
            }
        }
    }

    private func removePhoto(_ index: Int) {
        guard imageUrls.indices.contains(index) else { return }
        imageUrls.remove(at: index)
    }

    private func makeCover(_ index: Int) {
        guard imageUrls.indices.contains(index) else { return }
        let url = imageUrls.remove(at: index)
        imageUrls.insert(url, at: 0)
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard let uid = appState.userId else { return }
        uploading = true
        defer { uploading = false; photoItems = [] }
        var added: [String] = []
        for item in items.prefix(max(0, 8 - imageUrls.count)) {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            let data = UIImage(data: raw)?.jpegResized(maxDimension: 1600, quality: 0.8) ?? raw
            if let url = await appState.load({ try await $0.uploadImage(data, contentType: "image/jpeg", ext: "jpg", userId: uid) }) {
                added.append(url)
            }
        }
        if !added.isEmpty {
            imageUrls.append(contentsOf: added)
        }
    }
}
