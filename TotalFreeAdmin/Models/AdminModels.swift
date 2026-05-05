import Foundation

enum StaffRole: String, Codable, CaseIterable, Identifiable {
    case member
    case moderator
    case admin
    case superAdmin = "super_admin"
    case profileMissing = "profile_missing"
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .member: "Member"
        case .moderator: "Moderator"
        case .admin: "Admin"
        case .superAdmin: "Super admin"
        case .profileMissing: "No profile"
        case .unknown: "Unknown"
        }
    }

    var isStaff: Bool {
        self == .moderator || self == .admin || self == .superAdmin
    }

    var canManageAccess: Bool {
        self == .admin || self == .superAdmin
    }

    var canManageRoles: Bool {
        self == .superAdmin
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = StaffRole(rawValue: value) ?? .unknown
    }
}

enum AccountStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case active
    case suspended
    case banned
    case profileMissing = "profile_missing"
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "Pending"
        case .active: "Active"
        case .suspended: "Suspended"
        case .banned: "Banned"
        case .profileMissing: "No profile"
        case .unknown: "Unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = AccountStatus(rawValue: value) ?? .unknown
    }
}

enum PostStatus: String, Codable, Identifiable {
    case draft
    case pendingReview = "pending_review"
    case active
    case reserved
    case completed
    case closed
    case rejected
    case hidden
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: "Draft"
        case .pendingReview: "Pending review"
        case .active: "Available"
        case .reserved: "Connected"
        case .completed: "Completed"
        case .closed: "Closed"
        case .rejected: "Needs changes"
        case .hidden: "Hidden"
        case .unknown: "Unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = PostStatus(rawValue: value) ?? .unknown
    }
}

enum ReportStatus: String, Codable, Identifiable {
    case open
    case reviewing
    case resolved
    case dismissed
    case unknown

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ReportStatus(rawValue: value) ?? .unknown
    }
}

enum ReportSeverity: String, Codable {
    case normal
    case urgent
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = ReportSeverity(rawValue: value) ?? .unknown
    }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
    }
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct MeResponse: Decodable {
    let user: AppUser?
    let profile: Profile?
    let notifications: [NotificationItem]
}

struct AppUser: Decodable, Identifiable {
    let id: String
    let email: String?
}

struct Profile: Decodable {
    let userId: String
    let displayName: String
    let postalCode: String?
    let role: StaffRole
    let status: AccountStatus

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case postalCode = "postal_code"
        case role
        case status
    }
}

struct NotificationItem: Decodable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let readAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case body
        case link
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

struct AdminDashboard: Decodable {
    let stats: AdminStats
    let pendingPosts: [PendingPost]
    let reports: [SafetyReport]
    let inviteCodes: [InviteCode]
}

struct AdminStats: Decodable {
    let totalPosts: Int
    let draftPosts: Int
    let activePosts: Int
    let pendingPosts: Int
    let reservedPosts: Int
    let completedPosts: Int
    let closedPosts: Int
    let rejectedPosts: Int
    let hiddenPosts: Int
    let openReports: Int
    let members: Int
    let viewsToday: Int
    let uniqueVisitorsToday: Int
    let signedInVisitorsToday: Int
    let signInsToday: Int
    let views7d: Int
    let uniqueVisitors7d: Int
    let signedInVisitors7d: Int
    let signIns7d: Int
    let postStatusCounts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case totalPosts
        case draftPosts
        case activePosts
        case pendingPosts
        case reservedPosts
        case completedPosts
        case closedPosts
        case rejectedPosts
        case hiddenPosts
        case openReports
        case members
        case viewsToday
        case uniqueVisitorsToday
        case signedInVisitorsToday
        case signInsToday
        case views7d
        case uniqueVisitors7d
        case signedInVisitors7d
        case signIns7d
        case postStatusCounts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        totalPosts = try values.decodeIfPresent(Int.self, forKey: .totalPosts) ?? 0
        draftPosts = try values.decodeIfPresent(Int.self, forKey: .draftPosts) ?? 0
        activePosts = try values.decodeIfPresent(Int.self, forKey: .activePosts) ?? 0
        pendingPosts = try values.decodeIfPresent(Int.self, forKey: .pendingPosts) ?? 0
        reservedPosts = try values.decodeIfPresent(Int.self, forKey: .reservedPosts) ?? 0
        completedPosts = try values.decodeIfPresent(Int.self, forKey: .completedPosts) ?? 0
        closedPosts = try values.decodeIfPresent(Int.self, forKey: .closedPosts) ?? 0
        rejectedPosts = try values.decodeIfPresent(Int.self, forKey: .rejectedPosts) ?? 0
        hiddenPosts = try values.decodeIfPresent(Int.self, forKey: .hiddenPosts) ?? 0
        openReports = try values.decodeIfPresent(Int.self, forKey: .openReports) ?? 0
        members = try values.decodeIfPresent(Int.self, forKey: .members) ?? 0
        viewsToday = try values.decodeIfPresent(Int.self, forKey: .viewsToday) ?? 0
        uniqueVisitorsToday = try values.decodeIfPresent(Int.self, forKey: .uniqueVisitorsToday) ?? 0
        signedInVisitorsToday = try values.decodeIfPresent(Int.self, forKey: .signedInVisitorsToday) ?? 0
        signInsToday = try values.decodeIfPresent(Int.self, forKey: .signInsToday) ?? 0
        views7d = try values.decodeIfPresent(Int.self, forKey: .views7d) ?? 0
        uniqueVisitors7d = try values.decodeIfPresent(Int.self, forKey: .uniqueVisitors7d) ?? 0
        signedInVisitors7d = try values.decodeIfPresent(Int.self, forKey: .signedInVisitors7d) ?? 0
        signIns7d = try values.decodeIfPresent(Int.self, forKey: .signIns7d) ?? 0
        postStatusCounts = try values.decodeIfPresent([String: Int].self, forKey: .postStatusCounts) ?? [:]
    }
}

struct PendingPost: Decodable, Identifiable {
    let id: String
    let postType: String
    let title: String
    let description: String
    let category: String
    let condition: String
    let pickupArea: String
    let postalCode: String?
    let createdAt: String
    let owner: PostOwner
    let photos: [PostPhoto]

    var typeLabel: String { postType == "request" ? "Request" : "Offer" }
}

struct PostOwner: Decodable {
    let id: String
    let displayName: String
}

struct PostPhoto: Decodable, Identifiable {
    let id: String
    let status: String?
    let url: String?
}

struct AdminPostDetailResponse: Decodable {
    let item: AdminPostDetail
}

struct AdminPostDetail: Decodable, Identifiable {
    let id: String
    let postType: String
    let title: String
    let description: String
    let category: String
    let condition: String
    let pickupArea: String
    let postalCode: String?
    let pickupMethod: String?
    let availabilityWindow: String?
    let safetyNote: String?
    let status: PostStatus
    let moderationReason: String?
    let createdAt: String
    let updatedAt: String?
    let owner: AdminProfileSummary
    let photos: [PostPhoto]

    var typeLabel: String { postType == "request" ? "Request" : "Offer" }
}

struct AdminReportDetailResponse: Decodable {
    let report: SafetyReport
    let reporter: AdminProfileSummary?
    let targetPost: AdminPostDetail?
}

struct AdminProfileSummary: Decodable, Identifiable {
    let id: String
    let displayName: String
    let role: StaffRole?
    let status: AccountStatus?
    let postalCode: String?
}

struct SafetyReport: Decodable, Identifiable {
    let id: String
    let reporterId: String?
    let targetType: String
    let targetId: String
    let reason: String
    let details: String?
    let severity: ReportSeverity
    let status: ReportStatus
    let snapshot: ReportSnapshot?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId = "reporter_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case reason
        case details
        case severity
        case status
        case snapshot
        case createdAt = "created_at"
    }
}

struct ReportSnapshot: Decodable {
    let post: ReportPostSnapshot?
    let message: ReportMessageSnapshot?
}

struct ReportPostSnapshot: Decodable {
    let title: String?
    let description: String?
    let status: PostStatus?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case status
    }
}

struct ReportMessageSnapshot: Decodable {
    let body: String?
}

struct InviteCode: Decodable, Identifiable {
    let id: String
    let code: String
    let label: String?
    let status: String
    let maxUses: Int
    let usedCount: Int
    let expiresAt: String?
    let community: CommunitySummary?
}

struct CommunitySummary: Decodable {
    let id: String
    let name: String
    let slug: String?
}

struct AdminUsersResponse: Decodable {
    let viewer: AdminViewer
    let users: [AdminUser]
}

struct AdminViewer: Decodable {
    let id: String
    let role: StaffRole
    let permissions: AdminPermissions
}

struct AdminPermissions: Decodable {
    let canReview: Bool
    let canManageAccess: Bool
    let canManageRoles: Bool
}

struct AdminUser: Decodable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let role: StaffRole
    let status: AccountStatus
    let hasProfile: Bool
    let postalCode: String
    let community: CommunitySummary?
    let createdAt: String?
    let updatedAt: String?
    let lastSeenAt: String?
    let emailConfirmedAt: String?
    let isSelf: Bool
    let stats: UserStats
}

struct UserStats: Decodable {
    let totalPosts: Int
    let activePosts: Int
    let pendingPosts: Int
    let completedPosts: Int
    let responsesSent: Int
    let acceptedResponses: Int
    let reportsFiled: Int
    let openReportsFiled: Int
}

struct EmptyResponse: Decodable {}

struct ModeratePostResponse: Decodable {
    let item: PendingPost?
}

struct ReportMutationResponse: Decodable {
    let report: SafetyReport?
}

struct InviteCodeResponse: Decodable {
    let code: InviteCode
}

struct APIErrorBody: Decodable {
    let error: String
}
