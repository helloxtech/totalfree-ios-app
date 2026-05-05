import SwiftUI

struct AccessView: View {
    @EnvironmentObject private var appState: AppState
    @State private var code = ""
    @State private var label = ""
    @State private var maxUses = 3

    var inviteCodes: [InviteCode] {
        appState.dashboard?.inviteCodes ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Create invite code") {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Label", text: $label)
                    Stepper("Max uses: \(maxUses)", value: $maxUses, in: 1...500)
                    Button {
                        Task {
                            await appState.createInviteCode(
                                code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                                label: label,
                                maxUses: maxUses
                            )
                            code = ""
                            label = ""
                            maxUses = 3
                        }
                    } label: {
                        Label("Create code", systemImage: "plus.circle")
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }

                Section("Existing codes") {
                    if inviteCodes.isEmpty {
                        EmptyStateRow(title: "No invite codes yet", message: "Create one for a flyer or parent group.", systemImage: "key")
                    } else {
                        ForEach(inviteCodes) { invite in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(maskInvite(invite.code))
                                    .font(.headline)
                                Text("\(invite.usedCount)/\(invite.maxUses) used · \(invite.label ?? "No label")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Access")
            .refreshable { await appState.refreshDashboard() }
        }
    }
}

private func maskInvite(_ code: String) -> String {
    guard code.count > 4 else { return code }
    return String(code.prefix(3)) + "..." + String(code.suffix(3))
}
