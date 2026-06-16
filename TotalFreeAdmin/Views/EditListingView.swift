import SwiftUI

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
    @State private var saving = false

    init(listing: Listing, onSaved: @escaping (Listing) -> Void) {
        self.listing = listing
        self.onSaved = onSaved
        _title = State(initialValue: listing.title)
        _description = State(initialValue: listing.description)
        _category = State(initialValue: listing.category)
        _condition = State(initialValue: listing.condition ?? "good")
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
                    Section("Condition") {
                        Picker("Condition", selection: $condition) {
                            ForEach(AppConstants.conditions, id: \.self) { c in
                                Text(AppConstants.conditionLabels[c] ?? c).tag(c)
                            }
                        }
                    }
                }
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
                    condition: listing.isWanted ? nil : condition
                )
            }
            saving = false
            if let updated {
                appState.infoMessage = "Listing updated."
                onSaved(updated)
                dismiss()
            }
        }
    }
}
