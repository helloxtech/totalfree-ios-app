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

    var userRole: UserRole { UserRole(rawValue: role) ?? .user }
}

// MARK: - Listings

struct OwnerRef: Codable, Equatable { let id: String?; let name: String? }
struct SponsorRef: Codable, Equatable { let id: String?; let businessName: String?; let website: String?; let status: String? }
struct PartnerRef: Codable, Equatable { let id: String?; let name: String?; let website: String? }

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
    let imageUrl: String?
    let category: String?
    let sourceType: String?
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
    let text: String
    let createdAt: String?
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
        case "sponsor_approved": "Business approved"
        case "match_found": "New match"
        default: title
        }
    }

    var icon: String {
        switch type {
        case "request_new": "hands.sparkles"
        case "request_update": "arrow.triangle.2.circlepath"
        case "message_new": "bubble.left.and.bubble.right"
        case "listing_approved": "checkmark.seal"
        case "sponsor_approved": "building.2"
        case "match_found": "sparkles"
        default: "bell"
        }
    }
}

/// The `data` jsonb on a notification (keys are already camelCase in the DB triggers).
struct NotificationData: Codable, Equatable {
    let listingId: String?
    let requestId: String?
    let sponsorId: String?
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
    let listingId: String?
    let orgName: String?
    let website: String?
    let kind: String
    let note: String?
    let status: String
    let createdAt: String?
    let listings: ListingRef?
    let profiles: OwnerRef?

    var who: String { profiles?.name ?? "A member" }
    var what: String { orgName ?? listings?.title ?? website ?? "an organization" }
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
    let text: String
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

struct ModerateListingParams: Encodable { let p_id: String; let p_status: String }
struct SetUserRoleParams: Encodable { let target: String; let new_role: String }
struct ReportListingParams: Encodable { let p_listing: String; let p_reason: String; let p_note: String? }
struct CandidatesParams: Encodable { let p_status: String }
struct ReviewCandidateParams: Encodable { let p_candidate: String; let p_approve: Bool; let p_reason: String? }
struct ResolveClaimParams: Encodable { let p_claim: String; let p_approve: Bool }
struct SponsorStatusUpdate: Encodable { let status: String }
struct ListingEditUpdate: Encodable { let title: String; let description: String; let category: String; let condition: String? }
struct ListingResubmitUpdate: Encodable { let title: String; let description: String; let category: String; let condition: String?; let status: String }
struct ListingStatusUpdate: Encodable { let status: String }

struct PasswordGrantBody: Encodable { let email: String; let password: String }
struct RefreshTokenBody: Encodable { let refresh_token: String }
struct SignUpBody: Encodable { let email: String; let password: String; let data: [String: String] }

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
