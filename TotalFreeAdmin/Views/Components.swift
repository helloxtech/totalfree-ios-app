import SwiftUI

struct AccountMenu: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Menu {
            if let profile = appState.me?.profile {
                Text(profile.displayName)
                Text(profile.role.label)
            }
            Button(role: .destructive) {
                appState.signOut()
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
    }
}

struct MetricsStrip: View {
    let stats: AdminStats
    var onPending: (() -> Void)?
    var onReports: (() -> Void)?
    var onMembers: (() -> Void)?
    var onActive: (() -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MetricPill(label: "Pending", value: stats.pendingPosts, color: .orange, action: onPending)
                MetricPill(label: "Reports", value: stats.openReports, color: .red, action: onReports)
                MetricPill(label: "Members", value: stats.members, color: .green, action: onMembers)
                MetricPill(label: "Active", value: stats.activePosts, color: .blue, action: onActive)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
    }
}

struct MetricPill: View {
    let label: String
    let value: Int
    let color: Color
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(minWidth: 92, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ThumbnailPlaceholder: View {
    let photoCount: Int
    let kind: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14)
                .fill(kind == "request" ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: kind == "request" ? "hands.sparkles" : "shippingbox")
                        .font(.title2)
                        .foregroundStyle(kind == "request" ? .blue : .green)
                }
            if photoCount > 0 {
                Text("\(photoCount)")
                    .font(.caption2.bold())
                    .padding(6)
                    .background(.thinMaterial, in: Circle())
                    .accessibilityLabel("\(photoCount) photos")
            }
        }
    }
}

struct ChecklistItem: View {
    let text: String
    @Binding var isChecked: Bool

    init(_ text: String, isChecked: Binding<Bool>) {
        self.text = text
        self._isChecked = isChecked
    }

    var body: some View {
        Toggle(isOn: $isChecked) {
            Text(text)
                .font(.subheadline)
        }
        .toggleStyle(.checklist)
    }
}

private struct ChecklistToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? .green : .secondary)
                    .font(.title3)
                configuration.label
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "Checked" : "Not checked")
    }
}

private extension ToggleStyle where Self == ChecklistToggleStyle {
    static var checklist: ChecklistToggleStyle { ChecklistToggleStyle() }
}

struct EmptyStateRow: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct InfoCallout: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

func formatCategory(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.capitalized }
        .joined(separator: " ")
}
