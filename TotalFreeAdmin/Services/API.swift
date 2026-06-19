import Foundation

// =============================================================================
// Typed data functions over SupabaseClient — the app's equivalent of the web
// app's src/lib/api.js. Screens call these and never deal with raw rows.
// =============================================================================

extension SupabaseClient {

    private var listingSelect: String { SupabaseConfig.listingSelect }
    private var requestSelect: String {
        "*,listings(title,image_url,category,source_type),requester:requester_id(id,name),owner:owner_id(id,name)"
    }

    // MARK: Listings (public browse)

    func fetchActiveListings(limit: Int = 60) async throws -> [Listing] {
        try await restGet(
            "/rest/v1/listings?select=\(listingSelect)&status=eq.active&order=created_at.desc&limit=\(limit)",
            as: [Listing].self
        )
    }

    func searchListings(
        text: String = "", city: String = "", category: String = "",
        sourceType: String = "", kind: String = "", limit: Int = 48, offset: Int = 0
    ) async throws -> [Listing] {
        var q = "/rest/v1/listings?select=\(listingSelect)&status=eq.active&order=created_at.desc&limit=\(limit)&offset=\(offset)"
        if !category.isEmpty { q += "&category=eq.\(category)" }
        if !sourceType.isEmpty { q += "&source_type=eq.\(sourceType)" }
        if !kind.isEmpty { q += "&listing_kind=eq.\(kind)" }
        let s = text.pgSanitized
        if !s.isEmpty {
            let e = s.pgEncoded
            q += "&or=(title.ilike.*\(e)*,description.ilike.*\(e)*,source_label.ilike.*\(e)*,area.ilike.*\(e)*)"
        }
        let c = city.pgSanitized
        if !c.isEmpty {
            let e = c.pgEncoded
            q += "&or=(city.ilike.*\(e)*,area.ilike.*\(e)*)"
        }
        return try await restGet(q, as: [Listing].self)
    }

    /// Listings with coordinates inside a map viewport (lat/lng box), with the
    /// same filters as browse. Powers the map's "Search this area" so we fetch
    /// only what's on screen instead of the paginated list.
    func searchListingsInBounds(
        minLat: Double, maxLat: Double, minLng: Double, maxLng: Double,
        text: String = "", category: String = "", sourceType: String = "", kind: String = "",
        limit: Int = 300
    ) async throws -> [Listing] {
        var q = "/rest/v1/listings?select=\(listingSelect)&status=eq.active"
        q += "&lat=gte.\(minLat)&lat=lte.\(maxLat)&lng=gte.\(minLng)&lng=lte.\(maxLng)"
        q += "&order=created_at.desc&limit=\(limit)"
        if !category.isEmpty { q += "&category=eq.\(category)" }
        if !sourceType.isEmpty { q += "&source_type=eq.\(sourceType)" }
        if !kind.isEmpty { q += "&listing_kind=eq.\(kind)" }
        let s = text.pgSanitized
        if !s.isEmpty {
            let e = s.pgEncoded
            q += "&or=(title.ilike.*\(e)*,description.ilike.*\(e)*,source_label.ilike.*\(e)*,area.ilike.*\(e)*)"
        }
        return try await restGet(q, as: [Listing].self)
    }

    func fetchListing(id: String) async throws -> Listing? {
        let rows = try await restGet("/rest/v1/listings?select=\(listingSelect)&id=eq.\(id)&limit=1", as: [Listing].self)
        return rows.first
    }

    func fetchMyListings(ownerId: String) async throws -> [Listing] {
        try await restGet(
            "/rest/v1/listings?select=\(listingSelect)&owner_id=eq.\(ownerId)&order=created_at.desc",
            as: [Listing].self
        )
    }

    @discardableResult
    func createListing(
        ownerId: String, title: String, description: String, category: String, kind: String,
        condition: String?, quantity: Int?, neededBy: String?, city: String?, area: String?,
        imageUrls: [String] = [], lat: Double? = nil, lng: Double? = nil
    ) async throws -> Listing {
        let insert = ListingInsert(
            owner_id: ownerId,
            title: title,
            description: description,
            category: category,
            source_type: "totalfree",
            listing_kind: kind,
            condition: kind == "wanted" ? nil : condition,
            quantity: kind == "wanted" ? nil : (quantity ?? 1),
            needed_by: kind == "wanted" ? neededBy : nil,
            city: city,
            area: (area?.isEmpty == false ? area : city),
            image_url: imageUrls.first,
            image_urls: imageUrls.isEmpty ? nil : imageUrls,
            lat: lat,
            lng: lng,
            status: "pending_review"
        )
        let rows = try await restInsert("listings?select=\(listingSelect)", body: insert, returning: [Listing].self)
        guard let row = rows.first else { throw SupabaseError.server("The listing could not be created.") }
        return row
    }

    // MARK: Moderation (staff — RLS gates by has_perm('listing.review'))

    func fetchModerationQueue() async throws -> [Listing] {
        try await restGet(
            "/rest/v1/listings?select=\(listingSelect)&status=eq.pending_review&order=created_at.desc",
            as: [Listing].self
        )
    }

    /// Approve = "active", reject = "rejected" (status-only, via SECURITY DEFINER RPC).
    func moderateListing(id: String, status: String) async throws {
        try await rpc("moderate_listing", params: ModerateListingParams(p_id: id, p_status: status))
    }

    // MARK: Requests + messaging

    func createRequest(listingId: String, ownerId: String?, message: String, requesterId: String) async throws {
        try await restInsertNoReturn(
            "requests",
            body: RequestInsert(listing_id: listingId, owner_id: ownerId, requester_id: requesterId, message: message)
        )
    }

    /// Requests where I'm the requester OR the listing owner.
    func fetchMyRequests(userId: String) async throws -> [AppRequest] {
        try await restGet(
            "/rest/v1/requests?select=\(requestSelect)&or=(requester_id.eq.\(userId),owner_id.eq.\(userId))&order=updated_at.desc",
            as: [AppRequest].self
        )
    }

    func updateRequestStatus(id: String, status: String) async throws {
        try await restPatchNoReturn("/rest/v1/requests?id=eq.\(id)", body: RequestStatusUpdate(status: status))
    }

    func fetchMessages(requestId: String) async throws -> [Message] {
        try await restGet("/rest/v1/messages?select=*&request_id=eq.\(requestId)&order=created_at.asc", as: [Message].self)
    }

    func sendMessage(requestId: String, text: String, senderId: String) async throws {
        try await restInsertNoReturn(
            "messages",
            body: MessageInsert(request_id: requestId, sender_id: senderId, text: text)
        )
    }

    // MARK: Reports

    /// User-facing report of a listing (dedupes + may auto-hide via the RPC).
    func reportListing(listingId: String, reason: String, note: String?) async throws {
        try await rpc("report_listing", params: ReportListingParams(p_listing: listingId, p_reason: reason, p_note: note))
    }

    /// Staff report queue, enriched with listing titles for listing targets.
    func fetchReports() async throws -> [ReportRow] {
        let reports = try await restGet(
            "/rest/v1/reports?select=*,reporter:reporter_id(id,name)&order=created_at.desc",
            as: [Report].self
        )
        let listingIds = Array(Set(reports.filter { $0.targetType == "listing" }.map { $0.targetId }))
        var titles: [String: String] = [:]
        if !listingIds.isEmpty {
            let inList = listingIds.joined(separator: ",")
            let rows = try await restGet(
                "/rest/v1/listings?select=id,title&id=in.(\(inList))",
                as: [ListingTitleRow].self
            )
            for r in rows { titles[r.id] = r.title }
        }
        return reports.map { ReportRow(report: $0, listingTitle: titles[$0.targetId]) }
    }

    func resolveReport(id: String, status: String) async throws {
        try await restPatchNoReturn(
            "/rest/v1/reports?id=eq.\(id)",
            body: ReportResolveUpdate(status: status, reviewed_at: ISO8601DateFormatter().string(from: Date()))
        )
    }

    // MARK: Notifications

    func fetchNotifications(userId: String, limit: Int = 40) async throws -> [AppNotification] {
        try await restGet(
            "/rest/v1/notifications?select=*&user_id=eq.\(userId)&order=created_at.desc&limit=\(limit)",
            as: [AppNotification].self
        )
    }

    func markNotificationRead(id: String) async throws {
        try await restPatchNoReturn("/rest/v1/notifications?id=eq.\(id)", body: NotificationReadUpdate(read: true))
    }

    func deleteNotification(id: String) async throws {
        try await restDeleteNoReturn("/rest/v1/notifications?id=eq.\(id)")
    }

    func markAllNotificationsRead(userId: String) async throws {
        try await restPatchNoReturn(
            "/rest/v1/notifications?user_id=eq.\(userId)&read=eq.false",
            body: NotificationReadUpdate(read: true)
        )
    }

    // MARK: Profile

    func fetchProfile(userId: String) async throws -> Profile? {
        let rows = try await restGet("/rest/v1/profiles?select=*&id=eq.\(userId)&limit=1", as: [Profile].self)
        return rows.first
    }

    func updateProfileName(userId: String, name: String) async throws {
        try await restPatchNoReturn("/rest/v1/profiles?id=eq.\(userId)", body: ProfileNameUpdate(name: name))
    }

    func updateProfileAvatar(userId: String, url: String) async throws {
        try await restPatchNoReturn("/rest/v1/profiles?id=eq.\(userId)", body: ProfileAvatarUpdate(avatar_url: url))
    }

    // MARK: Admin users (Owner — set_user_role gated in SQL)

    func adminListUsers() async throws -> [AdminUserRow] {
        try await rpcDecoded("admin_list_users", params: EmptyParams(), as: [AdminUserRow].self)
    }

    func setUserRole(target: String, role: String) async throws {
        try await rpc("set_user_role", params: SetUserRoleParams(target: target, new_role: role))
    }

    // MARK: Device tokens (APNs)

    func registerDeviceToken(userId: String, token: String, apnsEnvironment: String, bundleId: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await restInsertNoReturn(
            "device_tokens",
            body: DeviceTokenInsert(
                user_id: userId,
                device_token: token,
                platform: "ios",
                apns_environment: apnsEnvironment,
                bundle_id: bundleId,
                is_active: true,
                last_error: "",
                last_seen_at: now,
                updated_at: now
            ),
            prefer: "resolution=merge-duplicates,return=minimal",
            onConflict: "user_id,device_token"
        )
    }

    func deleteDeviceToken(userId: String, token: String) async throws {
        try await restDeleteNoReturn("/rest/v1/device_tokens?user_id=eq.\(userId)&device_token=eq.\(token)")
    }

    // MARK: Permissions (my_perms RPC → the caller's effective permission keys)

    func fetchMyPerms() async throws -> [String] {
        try await rpcDecoded("my_perms", params: EmptyParams(), as: [String].self)
    }

    /// The caller's single entity kind: "Member" / "Business" / "Organization".
    func fetchMyEntityKind() async throws -> String {
        try await rpcDecoded("my_entity_kind", params: EmptyParams(), as: String.self)
    }

    /// Earned achievement badges for the signed-in user.
    func fetchMyBadges() async throws -> [AppBadge] {
        try await rpcDecoded("my_badges", params: EmptyParams(), as: [AppBadge].self)
    }

    // MARK: Edit any listing (listing.edit.any)

    @discardableResult
    func updateListing(id: String, title: String, description: String, category: String, condition: String?, resubmit: Bool = false) async throws -> Listing {
        if resubmit {
            try await restPatchNoReturn(
                "/rest/v1/listings?id=eq.\(id)",
                body: ListingResubmitUpdate(title: title, description: description, category: category, condition: condition, status: "pending_review")
            )
        } else {
            try await restPatchNoReturn(
                "/rest/v1/listings?id=eq.\(id)",
                body: ListingEditUpdate(title: title, description: description, category: category, condition: condition)
            )
        }
        guard let updated = try await fetchListing(id: id) else {
            throw SupabaseError.server("The listing was updated but could not be reloaded.")
        }
        return updated
    }

    // MARK: Owner self-service (own listing; RLS: listing.edit.own / listing.delete.own)

    /// Change only the status (withdraw → removed, complete → completed, etc.).
    func setListingStatus(id: String, status: String) async throws {
        try await restPatchNoReturn("/rest/v1/listings?id=eq.\(id)", body: ListingStatusUpdate(status: status))
    }

    func deleteListing(id: String) async throws {
        try await restDeleteNoReturn("/rest/v1/listings?id=eq.\(id)")
    }

    // MARK: Scanner candidates (listing.review)

    func fetchScanCandidates(status: String = "needs_review") async throws -> [ScanCandidate] {
        try await rpcDecoded("admin_list_candidates", params: CandidatesParams(p_status: status), as: [ScanCandidate].self)
    }

    func reviewScanCandidate(id: String, approve: Bool, reason: String?) async throws {
        try await rpc("admin_review_candidate", params: ReviewCandidateParams(p_candidate: id, p_approve: approve, p_reason: reason))
    }

    // MARK: Pipeline / analytics (analytics.view)

    func fetchPipelineStats() async throws -> [String: JSONValue] {
        try await rpcDecoded("admin_pipeline_stats", params: EmptyParams(), as: [String: JSONValue].self)
    }

    // MARK: Sponsors / businesses (business.approve)

    func fetchSponsorsForReview() async throws -> [Sponsor] {
        try await restGet("/rest/v1/sponsors?select=*&order=created_at.desc", as: [Sponsor].self)
    }

    func updateSponsorStatus(id: String, status: String) async throws {
        try await restPatchNoReturn("/rest/v1/sponsors?id=eq.\(id)", body: SponsorStatusUpdate(status: status))
    }

    // MARK: Org claims (claim.resolve)

    func fetchPendingClaims() async throws -> [OrgClaim] {
        try await rpcDecoded("admin_list_org_claims", params: EmptyParams(), as: [OrgClaim].self)
    }

    func resolveClaim(id: String, approve: Bool) async throws {
        try await rpc("admin_resolve_claim", params: ResolveClaimParams(p_claim: id, p_approve: approve))
    }

    // MARK: Conversations (message.read.any — RLS lets staff read every thread)

    func fetchAllRequests() async throws -> [AppRequest] {
        try await restGet("/rest/v1/requests?select=\(requestSelect)&order=updated_at.desc&limit=100", as: [AppRequest].self)
    }

    /// A single request by id (for deep-linking from a notification).
    func fetchRequest(id: String) async throws -> AppRequest? {
        let rows = try await restGet("/rest/v1/requests?select=\(requestSelect)&id=eq.\(id)&limit=1", as: [AppRequest].self)
        return rows.first
    }

    // MARK: Staff counts (for tab/row badges)

    func countPendingListings() async throws -> Int {
        try await count("/rest/v1/listings?status=eq.pending_review")
    }

    func countOpenReports() async throws -> Int {
        try await count("/rest/v1/reports?status=eq.open")
    }

    func countPendingClaims() async throws -> Int {
        try await count("/rest/v1/org_claims?status=eq.pending")
    }

    func countPendingSponsors() async throws -> Int {
        try await count("/rest/v1/sponsors?status=eq.pending_review")
    }

    /// Count of the member's own posts that need their attention (rejected → edit & resubmit).
    func countMyActionableListings(ownerId: String) async throws -> Int {
        try await count("/rest/v1/listings?owner_id=eq.\(ownerId)&status=eq.rejected")
    }

    /// Completed give-aways (handoffs) by this user — drives their Good Neighbour level.
    func countMyGifts(ownerId: String) async throws -> Int {
        try await count("/rest/v1/requests?status=eq.completed&owner_id=eq.\(ownerId)")
    }
}

private struct ListingTitleRow: Decodable { let id: String; let title: String }
struct EmptyParams: Encodable {}
