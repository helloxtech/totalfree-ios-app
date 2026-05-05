import Foundation

enum APIClientError: LocalizedError {
    case invalidURL
    case noResponse
    case server(String)
    case unauthorized
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The API URL is invalid."
        case .noResponse: "The server did not respond."
        case .server(let message): message
        case .unauthorized: "Please sign in again."
        case .decoding(let message): "Could not read server response: \(message)"
        }
    }
}

struct TotalFreeAPIClient {
    let baseURL: URL
    var accessToken: String?
    var urlSession: URLSession = .shared

    init(
        baseURL: URL = URL(string: "https://total-free-api.hurryupgo-b2d.workers.dev")!,
        accessToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
    }

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path, method: "GET", body: Optional<EmptyBody>.none)
    }

    func data(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.noResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw APIClientError.unauthorized }
            throw APIClientError.server(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return data
    }

    func post<Response: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path, method: "POST", body: body)
    }

    func patch<Response: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Response {
        try await request(path, method: "PATCH", body: body)
    }

    func delete<Response: Decodable>(_ path: String) async throws -> Response {
        try await request(path, method: "DELETE", body: Optional<EmptyBody>.none)
    }

    private func request<Response: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.noResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw APIClientError.unauthorized }
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIClientError.server(message)
        }

        if data.isEmpty, Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decoding(error.localizedDescription)
        }
    }
}

private struct EmptyBody: Encodable {}

struct RejectPostBody: Encodable {
    let reason: String
}

struct ResolveReportBody: Encodable {
    let decision: String
    let reason: String?
}

struct InviteCodeBody: Encodable {
    let code: String
    let label: String
    let maxUses: Int
}

struct UserRoleBody: Encodable {
    let role: String
}

struct UserStatusBody: Encodable {
    let status: String
}

struct PushDeviceRegistrationBody: Encodable {
    let deviceToken: String
    let platform = "ios"
    let app = "admin"
    let environment: String
    let bundleId: String

    init(deviceToken: String) {
        self.deviceToken = deviceToken
        self.environment = PushDeviceRegistrationBody.currentEnvironment
        self.bundleId = Bundle.main.bundleIdentifier ?? "ca.totalfree.admin"
    }

    private static var currentEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
