import Domain
import Foundation
import OSLog

/// Diagnostics only: counts, paths and decoding errors. Never names, notes or tokens.
let liveLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Zwischenzeit", category: "LiveAPI")

/// URLSession wrapper for `https://www.ttools.app/ttools/`. Adds the Bearer token,
/// maps status codes onto `APIError`, and on a 401 refreshes the token once
/// (shared by all concurrent requests, like the PWA) before retrying.
actor HTTPClient {
    struct Response {
        var status: Int
        var data: Data
    }

    let baseURL: URL
    let session: URLSession
    let store: any TokenStorage
    private var refreshTask: Task<Void, Error>?

    init(baseURL: URL, session: URLSession, store: any TokenStorage) {
        precondition(baseURL.scheme?.lowercased() == "https", "The backend must be reached over https.")
        self.baseURL = baseURL
        self.session = session
        self.store = store
    }

    // MARK: Authenticated reads

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await authorized(method: "GET", path: path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            liveLog.error("decode \(path, privacy: .public) as \(String(describing: T.self), privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            throw APIError.server(status: 0)
        }
    }

    /// Coding path and kind of a DecodingError, without the offending value.
    static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return String(describing: type(of: error)) }
        let path = { (c: [CodingKey]) in c.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".") }
        switch e {
        case .typeMismatch(let t, let c): return "typeMismatch \(t) at \(path(c.codingPath))"
        case .valueNotFound(let t, let c): return "valueNotFound \(t) at \(path(c.codingPath))"
        case .keyNotFound(let k, let c): return "keyNotFound \(k.stringValue) at \(path(c.codingPath))"
        case .dataCorrupted(let c): return "dataCorrupted at \(path(c.codingPath))"
        @unknown default: return "unknown"
        }
    }

    /// The retry after a refresh resends `body` unchanged, so only idempotent writes belong here.
    func authorized(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        guard let token = store.load()?.accessToken else { throw APIError.unauthorized }
        var response = try await send(method: method, path: path, query: query, body: body, bearer: token)
        if response.status == 401 {
            try await refreshAccessToken(failedToken: token)
            guard let fresh = store.load()?.accessToken else { throw APIError.unauthorized }
            response = try await send(method: method, path: path, query: query, body: body, bearer: fresh)
            if response.status == 401 {
                store.clear()
                throw APIError.unauthorized
            }
        }
        try Self.check(response.status)
        return response.data
    }

    // MARK: Token refresh

    /// One `rest/revalidate` at a time; callers that hit 401 meanwhile wait for it.
    private func refreshAccessToken(failedToken: String) async throws {
        if let refreshTask { return try await refreshTask.value }
        // Another caller already refreshed while this request was in flight.
        if let current = store.load()?.accessToken, current != failedToken { return }
        let task = Task { try await revalidate() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func revalidate() async throws {
        guard var tokens = store.load(), let refresh = tokens.refreshToken else {
            store.clear()
            throw APIError.unauthorized
        }
        let response = try await send(method: "POST", path: "rest/revalidate", body: Data("{}".utf8),
                                      headers: ["Refresh-Token": refresh])
        guard (200..<300).contains(response.status),
              let dto = try? JSONDecoder().decode(TokenDTO.self, from: response.data),
              let access = dto.accessToken else {
            store.clear()
            throw APIError.unauthorized
        }
        tokens.accessToken = access
        if let r = dto.refreshToken { tokens.refreshToken = r }
        store.save(tokens)
    }

    // MARK: Transport

    func send(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil,
              bearer: String? = nil, headers: [String: String] = [:]) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        // appendingPathComponent drops a trailing slash; the backend routes "rest/Termine/" with it.
        if path.hasSuffix("/"), !components.path.hasSuffix("/") { components.path += "/" }
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        do {
            let (data, response) = try await session.data(for: request)
            return Response(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch is URLError {
            throw APIError.offline
        }
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 404: throw APIError.notFound
        case 423: throw APIError.locked
        case 429: throw APIError.rateLimited
        default: throw APIError.server(status: status)
        }
    }
}
