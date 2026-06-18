import SwiftUI

// Shared, reusable UI used across the user-facing and staff screens.

enum Theme {
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.40) // community green
}

// MARK: - Date helpers

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()
private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

func parseDate(_ iso: String?) -> Date? {
    guard let iso, !iso.isEmpty else { return nil }
    return isoFractional.date(from: iso) ?? isoPlain.date(from: iso)
}

func relativeDate(_ iso: String?) -> String {
    guard let date = parseDate(iso) else { return "" }
    return relativeFormatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Badges

func colorForSource(_ sourceType: String) -> Color {
    switch sourceType {
    case "totalfree": Theme.accent
    case "sponsored": .orange
    case "partner": .blue
    case "learning", "external": .purple
    default: .gray
    }
}

struct SourceBadge: View {
    let sourceType: String
    var body: some View {
        Text(AppConstants.sourceLabel(sourceType))
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colorForSource(sourceType).opacity(0.15), in: Capsule())
            .foregroundStyle(colorForSource(sourceType))
            .accessibilityLabel("Source: \(AppConstants.sourceLabel(sourceType))")
    }
}

struct CategoryChip: View {
    let category: String
    var body: some View {
        Text("\(AppConstants.categoryEmoji[category] ?? "") \(AppConstants.categoryLabel(category))")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    private var label: String {
        switch status {
        case "pending_review": "Pending"
        case "active": "Active"
        case "rejected": "Rejected"
        case "removed": "Removed"
        case "archived": "Archived"
        case "claimed": "Claimed"
        case "completed": "Completed"
        case "open": "Open"
        case "accepted": "Accepted"
        case "declined": "Declined"
        case "cancelled": "Cancelled"
        case "dismissed": "Dismissed"
        case "warned": "Warned"
        default: status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private var color: Color {
        switch status {
        case "active", "accepted", "completed": .green
        case "pending_review", "open": .orange
        case "rejected", "removed", "declined", "cancelled": .red
        case "warned": .yellow
        default: .secondary
        }
    }
}

// MARK: - Listing visuals

struct ListingThumb: View {
    let url: String?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: placeholder
                    case .empty: ProgressView()
                    @unknown default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        Image(systemName: "gift")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ListingCard: View {
    let listing: Listing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ListingThumb(url: listing.imageUrl)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if listing.isWanted {
                        Text("WANTED").font(.caption2.bold()).foregroundStyle(.blue)
                    }
                    SourceBadge(sourceType: listing.sourceType)
                    Spacer(minLength: 0)
                    if listing.status != "active" { StatusBadge(status: listing.status) }
                }
                Text(listing.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    CategoryChip(category: listing.category)
                    Label(listing.locationText, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let created = listing.createdAt {
                    Text("\(listing.sourceLabelText) · \(relativeDate(created))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ContributorChip(listing: listing)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Small recognition chip on a listing: "Verified Organization/Business" for an
/// approved org/business, otherwise the giver's contributor level (hidden at 0).
struct ContributorChip: View {
    let listing: Listing

    private var entityKind: String {
        switch listing.sourceType {
        case "partner": return "Organization"
        case "sponsored": return "Business"
        default: return "Member"
        }
    }
    private var verified: Bool {
        (listing.sourceType == "sponsored" && listing.sponsors?.status == "active") ||
        (listing.sourceType == "partner" && listing.partners?.status == "active")
    }
    private var chip: (text: String, verified: Bool)? {
        if verified { return ("Verified \(entityKind)", true) }
        let gifts = listing.profiles?.giftsGiven ?? 0
        guard gifts >= 1 else { return nil }
        let lvl = ContributorLevel.forEntity(entityKind, gifts: gifts)
        return ("\(lvl.emoji) \(lvl.name)", false)
    }

    var body: some View {
        if let chip {
            HStack(spacing: 3) {
                if chip.verified { Image(systemName: "checkmark.seal.fill").font(.caption2) }
                Text(chip.text).font(.caption2.bold())
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(Theme.accent)
        }
    }
}

// MARK: - Generic pieces

struct EmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal)
    }
}

struct InfoCallout: View {
    let title: String
    let message: String
    var systemImage: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Small non-blocking confirmation banner (auto-dismisses; no title to read).
struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.accent, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.horizontal, 24)
    }
}
