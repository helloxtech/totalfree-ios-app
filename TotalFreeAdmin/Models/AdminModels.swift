import Foundation

// =============================================================================
// Codable models for the TotalFree Supabase schema.
//
// Server responses are decoded with `.convertFromSnakeCase`, so DB columns like
// `owner_id` / `image_url` arrive as `ownerId` / `imageUrl`. Insert + RPC bodies
// use explicit snake_case property names so they serialize to the exact column /
// argument names PostgREST expects.
// =============================================================================

// MARK: - Roles

enum UserRole: String, CaseIterable, Identifiable {
    case user, partner, sponsor, moderator, owner, admin
    var id: String { rawValue }

    var label: String {
        switch self {
        case .user: "Member"
        case .partner: "Organization"
        case .sponsor: "Business"
        case .moderator: "Moderator"
        case .owner: "Owner"
        case .admin: "Admin"
        }
    }

    /// Staff = anyone who can moderate (mirrors the web app's `isStaff`).
    var isStaff: Bool { self == .admin || self == .owner || self == .moderator }
    /// Owner-level = full control incl. user role management.
    var isOwner: Bool { self == .admin || self == .owner }
    /// Roles an Owner is allowed to assign from the app.
    static var assignable: [UserRole] { [.user, .partner, .sponsor, .moderator, .owner, .admin] }
}

// MARK: - Auth (Supabase GoTrue)

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
    let emailConfirmedAt: String?
    let confirmedAt: String?
    let userMetadata: [String: String]?

    var isVerified: Bool { (emailConfirmedAt?.isEmpty == false) || (confirmedAt?.isEmpty == false) }
    var displayName: String { userMetadata?["name"] ?? email ?? "Neighbour" }

    enum CodingKeys: String, CodingKey {
        case id, email, emailConfirmedAt, confirmedAt, userMetadata
    }

    // user_metadata values can be non-strings; decode leniently to [String:String].
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        emailConfirmedAt = try c.decodeIfPresent(String.self, forKey: .emailConfirmedAt)
        confirmedAt = try c.decodeIfPresent(String.self, forKey: .confirmedAt)
        if let raw = try? c.decodeIfPresent([String: JSONValue].self, forKey: .userMetadata) {
            userMetadata = raw.compactMapValues { $0.stringValue }
        } else {
            userMetadata = nil
        }
    }
}

/// Stored in the Keychain. Parsed from GoTrue token responses, then persisted /
/// reloaded with a plain coder (so the round trip stays camelCase-consistent).
struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double?
    let tokenType: String?
    let user: AuthUser?
}

/// Sign-up either returns a usable session (auto-confirm) or nothing until the
/// person confirms their email.
enum SignUpOutcome {
    case session(AuthSession)
    case needsEmailVerification
}

// MARK: - Profile

struct Profile: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let phoneVerified: Bool?
    let avatarUrl: String?
    let preferredLocale: String?

    var userRole: UserRole { UserRole(rawValue: role) ?? .user }
}

// MARK: - Listings

struct OwnerRef: Codable, Equatable { let id: String?; let name: String?; let giftsGiven: Int? }
struct SponsorRef: Codable, Equatable { let id: String?; let businessName: String?; let website: String?; let status: String? }
struct PartnerRef: Codable, Equatable { let id: String?; let name: String?; let website: String?; let status: String? }

struct Listing: Codable, Identifiable, Equatable {
    let id: String
    let ownerId: String?
    let title: String
    let description: String
    let category: String
    let sourceType: String
    let listingKind: String
    let condition: String?
    let quantity: Int?
    let neededBy: String?
    let city: String?
    let area: String?
    let lat: Double?
    let lng: Double?
    let imageUrl: String?
    let imageUrls: [String]?
    let imageFit: String?
    let externalUrl: String?
    let sourceLabel: String?
    let status: String
    let createdAt: String?
    let byDonation: Bool?
    let publicId: Int?
    let sponsors: SponsorRef?
    let partners: PartnerRef?
    let profiles: OwnerRef?

    var kind: String { listingKind }
    var isWanted: Bool { listingKind == "wanted" }
    var ownerName: String? { profiles?.name }

    /// WHO is behind the listing, resolved like the web normalizer.
    var sourceLabelText: String {
        sourceLabel ?? sponsors?.businessName ?? partners?.name ?? AppConstants.sourceLabel(sourceType)
    }

    var locationText: String {
        [area, city].compactMap { ($0?.isEmpty == false) ? $0 : nil }.first ?? "Metro Vancouver"
    }

    var categoryLabel: String { AppConstants.categoryLabel(category) }
    var conditionLabel: String? { AppConstants.conditionLabel(condition) }

    var prefersContainedImage: Bool {
        let fit = imageFit?.lowercased()
        if fit == "contain" { return true }
        if fit == "cover" { return false }
        if ownerId == nil, sourceLabel != nil { return true }
        return ["partner", "sponsored", "learning", "external"].contains(sourceType)
    }

    /// All photos to show (cover first); falls back to the single image_url.
    var galleryUrls: [String] {
        if let imageUrls, !imageUrls.isEmpty { return imageUrls }
        if let imageUrl, !imageUrl.isEmpty { return [imageUrl] }
        return []
    }
}

// MARK: - Requests + messages

struct ListingRef: Codable, Equatable {
    let title: String?
    let publicId: Int?
    let imageUrl: String?
    let imageFit: String?
    let category: String?
    let sourceType: String?

    var prefersContainedImage: Bool {
        let fit = imageFit?.lowercased()
        if fit == "contain" { return true }
        if fit == "cover" { return false }
        guard let sourceType else { return false }
        return ["partner", "sponsored", "learning", "external"].contains(sourceType)
    }
}

struct RequestPersonRef: Codable, Equatable {
    let id: String?
    let name: String?
}

struct AppRequest: Codable, Identifiable, Equatable {
    let id: String
    let listingId: String
    let requesterId: String
    let ownerId: String?
    let message: String
    let status: String
    let createdAt: String?
    let updatedAt: String?
    let listings: ListingRef?
    let requester: RequestPersonRef?
    let owner: RequestPersonRef?

    var itemTitle: String { listings?.title ?? "a listing" }
    var latestActivityAt: String? { updatedAt ?? createdAt }
    var requesterName: String { requester?.name ?? "a neighbour" }
    var ownerName: String { owner?.name ?? "the owner" }
}

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let requestId: String
    let senderId: String
    let kind: String?
    let text: String
    let imageUrl: String?
    let imageUrls: [String]?
    let lat: Double?
    let lng: Double?
    let createdAt: String?

    var galleryUrls: [String] {
        if let imageUrls, !imageUrls.isEmpty { return imageUrls }
        if let imageUrl, !imageUrl.isEmpty { return [imageUrl] }
        return []
    }
}

// MARK: - Reports

struct Report: Codable, Identifiable, Equatable {
    let id: String
    let targetId: String
    let targetType: String
    let reason: String
    let description: String?
    let reporterId: String?
    let status: String
    let createdAt: String?
    let reviewedAt: String?
    let reporter: OwnerRef?
}

/// A report plus the resolved listing title (enriched client-side, since the
/// polymorphic target has no foreign key to embed).
struct ReportRow: Identifiable, Equatable {
    let report: Report
    let listingTitle: String?
    var id: String { report.id }
}

// MARK: - Notifications

struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let read: Bool
    let createdAt: String?
    let data: NotificationData?

    var targetListingId: String? { data?.listingId }
    var targetRequestId: String? { data?.requestId }

    /// Clearer, distinct titles so "request" vs "message" alerts don't blur together.
    var displayTitle: String {
        switch type {
        case "request_new": "New request on your post"
        case "request_update": "Request update"
        case "message_new": "New message"
        case "listing_approved": "Post approved"
        case "listing_rejected": "Post needs changes"
        case "sponsor_approved": "Business approved"
        case "match_found": "New match"
        case "admin_report_new": "Report needs review"
        case "admin_listing_pending": "Post pending review"
        case "admin_business_pending": "Business needs approval"
        case "admin_org_claim_pending": "Organization claim needs review"
        default: title
        }
    }

    func localizedTitle(locale: String) -> String {
        let key = "notification.\(type)"
        let translated = L10n.text(key, locale: locale)
        return translated == key ? displayTitle : translated
    }

    var icon: String {
        switch type {
        case "request_new": "hands.sparkles"
        case "request_update": "arrow.triangle.2.circlepath"
        case "message_new": "bubble.left.and.bubble.right"
        case "listing_approved": "checkmark.seal"
        case "listing_rejected": "exclamationmark.triangle"
        case "sponsor_approved": "building.2"
        case "match_found": "sparkles"
        case "admin_report_new": "flag"
        case "admin_listing_pending": "rectangle.stack.badge.person.crop"
        case "admin_business_pending": "building.2"
        case "admin_org_claim_pending": "checkmark.seal"
        default: "bell"
        }
    }
}

/// The `data` jsonb on a notification (keys are already camelCase in the DB triggers).
struct NotificationData: Codable, Equatable {
    let listingId: String?
    let requestId: String?
    let sponsorId: String?
    let reportId: String?
    let claimId: String?
}

struct SavedSearch: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let label: String?
    let query: String?
    let category: String?
    let sourceType: String?
    let city: String?
    let alertMode: String
    let createdAt: String?

    var title: String {
        if let label, !label.isEmpty { return label }
        if let query, !query.isEmpty { return query }
        return "All free finds"
    }

    var details: String {
        let categoryText: String? = {
            guard let category, !category.isEmpty else { return nil }
            return AppConstants.categoryLabel(category)
        }()
        let sourceText: String? = {
            guard let sourceType, !sourceType.isEmpty else { return nil }
            return AppConstants.sourceLabel(sourceType)
        }()
        return [
            city?.isEmpty == false ? city : nil,
            categoryText,
            sourceText,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct NotificationPrefs: Codable, Equatable {
    var userId: String?
    var pushEnabled: Bool
    var emailEnabled: Bool
    var savedSearchAlerts: Bool
    var requestUpdates: Bool
    var messageAlerts: Bool
    var sponsorOffers: Bool
    var communityDigest: Bool
    var quietHoursStart: Int?
    var quietHoursEnd: Int?
    var updatedAt: String?

    static func defaults(userId: String? = nil) -> NotificationPrefs {
        NotificationPrefs(
            userId: userId,
            pushEnabled: true,
            emailEnabled: true,
            savedSearchAlerts: true,
            requestUpdates: true,
            messageAlerts: true,
            sponsorOffers: false,
            communityDigest: true,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            updatedAt: nil
        )
    }
}

// MARK: - Admin users (from admin_list_users RPC)

struct AdminUserRow: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let role: String?
    let email: String?
    let createdAt: String?

    var userRole: UserRole { UserRole(rawValue: role ?? "user") ?? .user }
    var displayName: String { (name?.isEmpty == false ? name : nil) ?? email ?? "Neighbour" }
}

// MARK: - Permissions (keys from public.permissions; gated by my_perms())

enum Perm {
    static let listingEditOwn = "listing.edit.own"
    static let listingDeleteOwn = "listing.delete.own"
    static let listingReview = "listing.review"
    static let listingEditAny = "listing.edit.any"
    static let listingDeleteAny = "listing.delete.any"
    static let reportResolve = "report.resolve"
    static let claimResolve = "claim.resolve"
    static let businessApprove = "business.approve"
    static let messageReadAny = "message.read.any"
    static let analyticsView = "analytics.view"
    static let userView = "user.view"
    static let userManage = "user.manage"
    static let teamManage = "team.manage"
    static let roleManage = "role.manage"

    /// Any of these means the person should see the staff area.
    static let staffArea: [String] = [
        listingReview, listingEditAny, listingDeleteAny, reportResolve, claimResolve,
        businessApprove, messageReadAny, analyticsView, userView, userManage, teamManage, roleManage,
    ]
}

// MARK: - Sponsors / claims / scanner candidates (staff surfaces)

struct Sponsor: Codable, Identifiable, Equatable {
    let id: String
    let ownerId: String?
    let businessName: String
    let description: String?
    let website: String?
    let logoUrl: String?
    let status: String
    let createdAt: String?
}

struct OrgClaim: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let claimantName: String?
    let claimantEmail: String?
    let claimantEmailDomain: String?
    let listingId: String?
    let listingTitle: String?
    let listingPublicId: Int?
    let listingSourceType: String?
    let listingSourceLabel: String?
    let listingExternalUrl: String?
    let listingDomain: String?
    let orgName: String?
    let website: String?
    let websiteDomain: String?
    let kind: String
    let note: String?
    let status: String
    let createdAt: String?
    let reviewedAt: String?
    let listings: ListingRef?
    let profiles: OwnerRef?

    var who: String { claimantName ?? profiles?.name ?? "A member" }
    var email: String? { claimantEmail?.isEmpty == false ? claimantEmail : nil }
    var emailDomain: String? { claimantEmailDomain?.isEmpty == false ? claimantEmailDomain : nil }
    var referenceDomain: String? {
        if let websiteDomain, !websiteDomain.isEmpty { return websiteDomain }
        if let listingDomain, !listingDomain.isEmpty { return listingDomain }
        return nil
    }
    var listingDisplay: String? {
        let title = listingTitle ?? listings?.title
        guard let title, !title.isEmpty else { return nil }
        if let listingPublicId { return "TF-\(listingPublicId) · \(title)" }
        if let publicId = listings?.publicId { return "TF-\(publicId) · \(title)" }
        return title
    }
    var what: String { orgName ?? listingTitle ?? listings?.title ?? website ?? "an organization" }
    var typeLabel: String { kind == "register" ? "New organization" : "Listing claim" }
    var domainStatus: String {
        guard let emailDomain, let referenceDomain else { return "Needs evidence" }
        return emailDomain == referenceDomain ? "Domain match" : "Manual check"
    }
    var hasDomainMatch: Bool {
        guard let emailDomain, let referenceDomain else { return false }
        return emailDomain == referenceDomain
    }
    var hasDomainMismatch: Bool {
        guard let emailDomain, let referenceDomain else { return false }
        return emailDomain != referenceDomain
    }
}

struct CandidatePayload: Codable, Equatable {
    let title: String?
    let city: String?
    let area: String?
    let category: String?
    let description: String?
    let externalUrl: String?
    let url: String?
    var link: String? { externalUrl ?? url }
}

struct ScanCandidate: Codable, Identifiable, Equatable {
    let id: String
    let agent: String?
    let sourceDomain: String?
    let evidenceQuote: String?
    let status: String
    let confidence: Double?
    let createdAt: String?
    let payload: CandidatePayload?

    var title: String { payload?.title ?? "(untitled find)" }
    var confidencePct: String? { confidence.map { "\(Int(($0 * 100).rounded()))%" } }
}

struct ModeratorDutyPerson: Codable, Identifiable, Equatable {
    let userId: String
    let name: String
    let email: String?
    let role: String?

    var id: String { userId }
    var displayRole: String { UserRole(rawValue: role ?? "moderator")?.label ?? "Moderator" }
}

struct ModeratorDutyShift: Codable, Identifiable, Equatable {
    let dutyDate: String
    let userId: String
    let name: String
    let email: String?
    let role: String?

    var id: String { "\(dutyDate)-\(userId)" }
    var person: ModeratorDutyPerson {
        ModeratorDutyPerson(userId: userId, name: name, email: email, role: role)
    }
}

// MARK: - Insert / update / RPC bodies (snake_case = column/argument names)

struct ListingInsert: Encodable {
    let owner_id: String
    let title: String
    let description: String
    let category: String
    let source_type: String
    let listing_kind: String
    let condition: String?
    let quantity: Int?
    let needed_by: String?
    let city: String?
    let area: String?
    let image_url: String?
    let image_urls: [String]?
    let lat: Double?
    let lng: Double?
    let status: String
}

struct RequestInsert: Encodable {
    let listing_id: String
    let owner_id: String?
    let requester_id: String
    let message: String
}

struct MessageInsert: Encodable {
    let request_id: String
    let sender_id: String
    let kind: String
    let text: String
    let image_url: String?
    let image_urls: [String]?
    let lat: Double?
    let lng: Double?
}

struct DeviceTokenInsert: Encodable {
    let user_id: String
    let device_token: String
    let platform: String
    let apns_environment: String
    let bundle_id: String
    let is_active: Bool
    let last_error: String
    let last_seen_at: String
    let updated_at: String
}

struct RequestStatusUpdate: Encodable { let status: String }
struct ReportResolveUpdate: Encodable { let status: String; let reviewed_at: String }
struct NotificationReadUpdate: Encodable { let read: Bool }
struct ProfileNameUpdate: Encodable { let name: String }
struct ProfileAvatarUpdate: Encodable { let avatar_url: String }
struct ProfileLocaleUpdate: Encodable { let preferred_locale: String }
struct NotificationPrefsSeed: Encodable { let user_id: String }

struct NotificationPrefsUpdate: Encodable {
    let push_enabled: Bool
    let email_enabled: Bool
    let saved_search_alerts: Bool
    let request_updates: Bool
    let message_alerts: Bool
    let sponsor_offers: Bool
    let community_digest: Bool
    let updated_at: String
}

struct ModerateListingParams: Encodable { let p_id: String; let p_status: String }
struct SetUserRoleParams: Encodable { let target: String; let new_role: String }
struct ReportListingParams: Encodable { let p_listing: String; let p_reason: String; let p_note: String? }
struct CandidatesParams: Encodable { let p_status: String }
struct ReviewCandidateParams: Encodable { let p_candidate: String; let p_approve: Bool; let p_reason: String? }
struct ClaimListingParams: Encodable { let p_listing: String; let p_org_name: String; let p_website: String; let p_note: String }
struct ResolveClaimParams: Encodable { let p_claim: String; let p_approve: Bool }
struct ModeratorDutyListParams: Encodable { let p_start: String?; let p_days: Int }
struct ModeratorDutySetParams: Encodable { let p_date: String; let p_user_ids: [String] }
struct ModeratorDutyBulkParams: Encodable { let p_dates: [String]; let p_user_ids: [String] }
struct SponsorStatusUpdate: Encodable { let status: String }
struct ListingEditUpdate: Encodable {
    let title: String
    let description: String
    let category: String
    let condition: String?
    let image_url: String?
    let image_urls: [String]?
    let include_images: Bool

    enum CodingKeys: String, CodingKey { case title, description, category, condition, image_url, image_urls }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(condition, forKey: .condition)
        if include_images {
            if let image_url { try c.encode(image_url, forKey: .image_url) }
            else { try c.encodeNil(forKey: .image_url) }
            if let image_urls { try c.encode(image_urls, forKey: .image_urls) }
            else { try c.encodeNil(forKey: .image_urls) }
        }
    }
}

struct ListingResubmitUpdate: Encodable {
    let title: String
    let description: String
    let category: String
    let condition: String?
    let image_url: String?
    let image_urls: [String]?
    let include_images: Bool
    let status: String

    enum CodingKeys: String, CodingKey { case title, description, category, condition, image_url, image_urls, status }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(condition, forKey: .condition)
        if include_images {
            if let image_url { try c.encode(image_url, forKey: .image_url) }
            else { try c.encodeNil(forKey: .image_url) }
            if let image_urls { try c.encode(image_urls, forKey: .image_urls) }
            else { try c.encodeNil(forKey: .image_urls) }
        }
        try c.encode(status, forKey: .status)
    }
}
struct ListingStatusUpdate: Encodable { let status: String }

struct PasswordGrantBody: Encodable { let email: String; let password: String }
struct RefreshTokenBody: Encodable { let refresh_token: String }
struct SignUpBody: Encodable { let email: String; let password: String; let data: [String: String] }

struct TranslateListingBody: Encodable { let listingId: String; let locale: String }
struct ListingTranslation: Codable, Equatable {
    let title: String?
    let description: String?
    let locale: String?
    let source: String?
    let provider: String?
}

// MARK: - Contributor recognition (entity-aware levels)

/// A level on one of three contributor tracks — Member (Good Neighbour),
/// Business, or Organization — by completed give-aways. Mirrored on web.
/// Admin/Moderator are staff roles and don't have a contributor track.
struct ContributorLevel {
    let name: String
    let emoji: String
    let min: Int
    let next: (min: Int, name: String)?
    let unit: String   // "gift" / "offer" / "contribution"

    private typealias Tier = (min: Int, name: String, emoji: String)
    private static let neighbour: [Tier] = [
        (0, "New Neighbour", "👋"), (1, "Kind Neighbour", "🌱"), (5, "Good Neighbour", "🤝"),
        (15, "Generous Neighbour", "🎁"), (40, "Neighbourhood Champion", "🏅"), (100, "Local Legend", "🌟"),
    ]
    private static let business: [Tier] = [
        (0, "Local Business", "🏪"), (5, "Friendly Local Business", "💚"), (25, "Community Champion", "🌟"),
    ]
    private static let organization: [Tier] = [
        (0, "Community Organization", "🏛️"), (5, "Community Partner", "🤝"), (25, "Community Pillar", "🏆"),
    ]

    /// Pick the track by entity kind (Member / Business / Organization).
    static func forEntity(_ kind: String, gifts: Int) -> ContributorLevel {
        let ladder: [Tier]
        let unit: String
        switch kind {
        case "Business": ladder = business; unit = "offer"
        case "Organization": ladder = organization; unit = "contribution"
        default: ladder = neighbour; unit = "gift"
        }
        var idx = 0
        for (i, t) in ladder.enumerated() where gifts >= t.min { idx = i }
        let cur = ladder[idx]
        let nxt: (min: Int, name: String)? = idx + 1 < ladder.count ? (ladder[idx + 1].min, ladder[idx + 1].name) : nil
        return ContributorLevel(name: cur.name, emoji: cur.emoji, min: cur.min, next: nxt, unit: unit)
    }
}

/// An earned achievement badge (from the my_badges() RPC).
struct AppBadge: Codable, Identifiable, Equatable {
    let key: String
    let label: String
    let emoji: String
    let count: Int?
    var id: String { key }
}

// MARK: - Lightweight JSON value (for user_metadata decoding)

enum JSONValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool), null
    case object([String: JSONValue]), array([JSONValue])

    var stringValue: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .bool(let b): String(b)
        default: nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
