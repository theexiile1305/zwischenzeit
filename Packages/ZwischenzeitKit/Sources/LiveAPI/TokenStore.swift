import Domain
import Foundation
import Security

/// Access + refresh token pair from `rest/login`, `rest/mfa` and `rest/revalidate`.
public struct Tokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var mandantId: String?
    /// "<Einrichtung>" the user signed in with; the drawer shows it as the practice name.
    public var practice: String?

    public init(accessToken: String, refreshToken: String?, mandantId: String? = nil, practice: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.mandantId = mandantId
        self.practice = practice
    }
}

public protocol TokenStorage: Sendable {
    func load() -> Tokens?
    func save(_ tokens: Tokens)
    func clear()
}

/// One generic-password item, this device only, readable after first unlock
/// (background refresh runs while the phone is locked).
public struct KeychainTokenStore: TokenStorage {
    let service: String
    let account = "tokens"

    public init(service: String = (Bundle.main.bundleIdentifier ?? "Zwischenzeit") + ".session") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    public func save(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?

    public init(_ tokens: Tokens? = nil) { self.tokens = tokens }

    public func load() -> Tokens? { lock.withLock { tokens } }
    public func save(_ tokens: Tokens) { lock.withLock { self.tokens = tokens } }
    public func clear() { lock.withLock { tokens = nil } }
}

/// The access token's payload. The signature is the server's business; we only read claims.
struct TokenClaims: Decodable {
    var mitarbeiter: FlexibleID?
    var benutzer: FlexibleID?
    var roles: [String]?
    var exp: Double?

    init(jwt: String) throws {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw APIError.unauthorized }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64) else { throw APIError.unauthorized }
        self = try JSONDecoder().decode(TokenClaims.self, from: data)
    }
}
