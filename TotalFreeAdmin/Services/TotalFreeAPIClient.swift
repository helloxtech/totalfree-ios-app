import Foundation

// =============================================================================
// SupabaseClient — the thin transport the whole app talks to Supabase through.
//
// It speaks three Supabase surfaces directly (no custom server in between):
//   • GoTrue   /auth/v1/...   — sign in / sign up / refresh
//   • PostgREST /rest/v1/...  — table reads & writes (RLS is the security boundary)
//   • RPC      /rest/v1/rpc/  — SECURITY DEFINER functions (moderate_listing, …)
//
// High-level, typed data functions live in the `extension` in API.swift.
// =============================================================================

enum SupabaseError: LocalizedError {
    case invalidURL
    case noResponse
    case unauthorized
    case forbidden
    case server(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Could not build the request URL."
        case .noResponse: "The server did not respond."
        case .unauthorized: "Please sign in again."
        case .forbidden: "You don't have permission to do that."
        case .server(let m): m
        case .decoding(let m): "Could not read the server response: \(m)"
        }
    }
}

struct SupabaseClient {
    /// The signed-in user's JWT, when available. Public reads work without it
    /// (the publishable key is sent as the anon identity).
    var accessToken: String? = nil
    var urlSession: URLSession = .shared

    private var baseURL: URL { SupabaseConfig.url }
    private var apiKey: String { SupabaseConfig.publishableKey }

    /// Shared decoder for all server responses: DB snake_case -> Swift camelCase.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder = JSONEncoder()

    // MARK: - Auth

    func signIn(email: String, password: String) async throws -> AuthSession {
        let data = try await send(
            path: "/auth/v1/token",
            method: "POST",
            query: "grant_type=password",
            body: PasswordGrantBody(email: email, password: password),
            authed: false
        )
        return try decode(AuthSession.self, from: data)
    }

    func signUp(email: String, password: String, name: String) async throws -> SignUpOutcome {
        let data = try await send(
            path: "/auth/v1/signup",
            method: "POST",
            query: Self.queryString([
                URLQueryItem(name: "redirect_to", value: SupabaseConfig.emailConfirmationRedirectURL.absoluteString),
            ]),
            body: SignUpBody(email: email, password: password, data: ["name": name]),
            authed: false
        )
        // Auto-confirm projects return a full session; confirmation-required
        // projects return just the created user (no access_token yet).
        if let session = try? decode(AuthSession.self, from: data), !session.accessToken.isEmpty {
            return .session(session)
        }
        return .needsEmailVerification
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        let data = try await send(
            path: "/auth/v1/token",
            method: "POST",
            query: "grant_type=refresh_token",
            body: RefreshTokenBody(refresh_token: refreshToken),
            authed: false
        )
        return try decode(AuthSession.self, from: data)
    }

    func signOutRemote() async {
        _ = try? await send(path: "/auth/v1/logout", method: "POST", body: Optional<PasswordGrantBody>.none)
    }

    // MARK: - REST (PostgREST)

    /// GET a fully-formed REST path (caller supplies the query string).
    func restGet<T: Decodable>(_ pathWithQuery: String, as type: T.Type) async throws -> T {
        let data = try await sendRaw(path: pathWithQuery, method: "GET", bodyData: nil, prefer: nil)
        return try decode(T.self, from: data)
    }

    @discardableResult
    func restInsert<T: Decodable, B: Encodable>(
        _ table: String, body: B, returning: T.Type, prefer: String = "return=representation", onConflict: String? = nil
    ) async throws -> T {
        var path = "/rest/v1/\(table)"
        if let onConflict { path += "?on_conflict=\(onConflict)" }
        let data = try await sendRaw(path: path, method: "POST", bodyData: try Self.encoder.encode(body), prefer: prefer)
        return try decode(T.self, from: data)
    }

    func restInsertNoReturn<B: Encodable>(_ table: String, body: B, prefer: String = "return=minimal", onConflict: String? = nil) async throws {
        var path = "/rest/v1/\(table)"
        if let onConflict { path += "?on_conflict=\(onConflict)" }
        _ = try await sendRaw(path: path, method: "POST", bodyData: try Self.encoder.encode(body), prefer: prefer)
    }

    func restPatchNoReturn<B: Encodable>(_ pathWithQuery: String, body: B) async throws {
        _ = try await sendRaw(path: pathWithQuery, method: "PATCH", bodyData: try Self.encoder.encode(body), prefer: "return=minimal")
    }

    func restDeleteNoReturn(_ pathWithQuery: String) async throws {
        _ = try await sendRaw(path: pathWithQuery, method: "DELETE", bodyData: nil, prefer: "return=minimal")
    }

    // MARK: - RPC

    @discardableResult
    func rpc<B: Encodable>(_ fn: String, params: B) async throws -> Data {
        try await sendRaw(path: "/rest/v1/rpc/\(fn)", method: "POST", bodyData: try Self.encoder.encode(params), prefer: nil)
    }

    func rpcDecoded<T: Decodable, B: Encodable>(_ fn: String, params: B, as type: T.Type) async throws -> T {
        let data = try await rpc(fn, params: params)
        return try decode(T.self, from: data)
    }

    // MARK: - Storage (Supabase Storage; bucket listing-media is public)

    /// Uploads image bytes to `{userId}/{uuid}.{ext}` (RLS requires the first
    /// folder to equal the user id) and returns the public URL.
    func uploadImage(_ data: Data, contentType: String, ext: String, userId: String) async throws -> String {
        let path = "\(userId)/\(UUID().uuidString).\(ext)"
        guard let url = URL(string: "/storage/v1/object/listing-media/\(path)", relativeTo: baseURL) else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("3600", forHTTPHeaderField: "Cache-Control")
        request.httpBody = data

        let (respData, response) = try await urlSession.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.noResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseError.unauthorized }
            if http.statusCode == 403 { throw SupabaseError.forbidden }
            throw SupabaseError.server(Self.errorMessage(from: respData, status: http.statusCode))
        }
        return "\(baseURL.absoluteString)/storage/v1/object/public/listing-media/\(path)"
    }

    /// Exact row count via PostgREST's Content-Range header (cheap; fetches no rows).
    func count(_ pathWithQuery: String) async throws -> Int {
        guard let url = URL(string: pathWithQuery, relativeTo: baseURL) else { throw SupabaseError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        request.setValue("0-0", forHTTPHeaderField: "Range")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return 0 }
        // Content-Range looks like "0-0/123" or "*/0".
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let totalPart = cr.split(separator: "/").last, let total = Int(totalPart) {
            return total
        }
        return 0
    }

    // MARK: - Transport

    private func send<B: Encodable>(
        path: String, method: String, query: String? = nil, body: B?, authed: Bool = true
    ) async throws -> Data {
        let bodyData = try body.map { try Self.encoder.encode($0) }
        let full = query.map { "\(path)?\($0)" } ?? path
        return try await sendRaw(path: full, method: method, bodyData: bodyData, prefer: nil, forceAnon: !authed)
    }

    private func sendRaw(path: String, method: String, bodyData: Data?, prefer: String?, forceAnon: Bool = false) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        let bearer = (!forceAnon && accessToken != nil) ? accessToken! : apiKey
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = bodyData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SupabaseError.noResponse
        }
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.noResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseError.unauthorized }
            if http.statusCode == 403 { throw SupabaseError.forbidden }
            throw SupabaseError.server(Self.errorMessage(from: data, status: http.statusCode))
        }
        return data
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw SupabaseError.decoding(String(describing: error)) }
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error_description", "msg", "error", "hint", "details"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty, s.count < 300 { return s }
        return "Request failed (\(status))."
    }

    private static func queryString(_ items: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }
}

// PostgREST percent-encoding for dynamic values placed inside a query string.
// Structural characters (commas, parentheses, dots, asterisks) are left literal
// because PostgREST needs them; only unsafe characters in user text are encoded.
extension String {
    var pgEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~ ")
        let s = addingPercentEncoding(withAllowedCharacters: allowed) ?? self
        return s.replacingOccurrences(of: " ", with: "%20")
    }

    /// Strip characters that would break a PostgREST `ilike` pattern / `or` group.
    var pgSanitized: String {
        components(separatedBy: CharacterSet(charactersIn: "%,()*")).joined().trimmingCharacters(in: .whitespaces)
    }
}
