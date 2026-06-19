import Foundation

// Connection details for the TotalFree Supabase backend (project ettemffrunjqoqwkaxmg).
//
// The *publishable* key is safe to ship in a client bundle — Row Level Security
// is the real security boundary, exactly like the web app. NEVER put the
// service_role key here.
enum SupabaseConfig {
    static let url = URL(string: "https://ettemffrunjqoqwkaxmg.supabase.co")!
    static let publishableKey = "sb_publishable_H6GXKlP7S91LCqBqCaeeLA_mw4kYAOm"
    static let emailConfirmationRedirectURL = URL(string: "https://totalfree.ca/")!
    static let mobileAuthCallbackScheme = "ca.totalfree.admin"
    static let mobileAuthStartURL = URL(string: "https://totalfree.ca/auth/mobile-start")!
    static let mobileAuthRedirectURL = URL(string: "https://totalfree.ca/auth/mobile-callback")!

    static func isMobileAuthRedirect(_ url: URL) -> Bool {
        url.scheme == mobileAuthCallbackScheme && url.host == "auth" && url.path == "/callback"
    }

    // PostgREST embed used everywhere a listing is read, so cards/detail get the
    // owner name + sponsor/partner label in one round trip.
    static let listingSelect =
        "*,sponsors(id,business_name,website,status),partners(id,name,website,status),profiles:owner_id(id,name,gifts_given)"
}

// Shared vocabulary mirrored from the web app's src/lib/constants.js so the
// posting form and filters speak the same language as the rest of the platform.
enum AppConstants {
    static let categories = ["furniture", "home", "school", "kids", "sports", "food", "clothing", "learning"]
    static let browseCategories = categories.filter { $0 != "learning" }

    static let categoryLabels: [String: String] = [
        "furniture": "Furniture", "home": "Household", "school": "School", "kids": "Kids",
        "sports": "Sports", "food": "Food", "clothing": "Clothing", "learning": "Learning",
    ]

    static let categoryEmoji: [String: String] = [
        "furniture": "🪑", "home": "🏡", "school": "📚", "kids": "🧸",
        "sports": "⚽", "food": "☕", "clothing": "🧥", "learning": "🎓",
    ]

    static let conditions = ["new", "like_new", "good", "fair", "for_parts"]
    static let conditionLabels: [String: String] = [
        "new": "New", "like_new": "Like new", "good": "Good",
        "fair": "Fair", "for_parts": "For parts / repair",
    ]

    static let kindLabels: [String: String] = ["offer": "Free to give", "wanted": "Wanted"]

    // Source label = WHO is behind a listing, in plain words.
    static let sourceLabels: [String: String] = [
        "totalfree": "Neighbour", "sponsored": "Business",
        "partner": "Organization", "learning": "Online", "external": "Online",
    ]

    struct SourceBucket: Identifiable { let id: String; let label: String }
    static let sourceBuckets: [SourceBucket] = [
        SourceBucket(id: "totalfree", label: "Neighbour"),
        SourceBucket(id: "partner", label: "Organization"),
        SourceBucket(id: "sponsored", label: "Business"),
    ]

    static func categoryLabel(_ key: String) -> String {
        categoryLabels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func conditionLabel(_ key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        return conditionLabels[key] ?? key
    }

    static func sourceLabel(_ sourceType: String) -> String {
        sourceLabels[sourceType] ?? "Listing"
    }
}
