import Foundation

/// The backend sends ids as numbers in some places and strings in others.
struct FlexibleID: Decodable, Hashable, CustomStringConvertible, Sendable {
    let raw: String
    var description: String { raw }

    init(_ raw: String) { self.raw = raw }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) { raw = String(i) }
        else if let d = try? c.decode(Double.self) { raw = String(Int64(d)) }
        else { raw = try c.decode(String.self) }
    }

    /// The same rule for a value from `JSONSerialization` (used where raw JSON is kept).
    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: s
        case let n as NSNumber: String(n.int64Value)
        default: nil
        }
    }
}

/// Number that sometimes arrives as a string ("30").
struct FlexibleInt: Decodable, Hashable, Sendable {
    let value: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = Int(d) }
        else if let s = try? c.decode(String.self), let i = Int(s) { value = i }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a number") }
    }
}

/// `rest/login`, `rest/mfa`, `rest/revalidate`.
struct TokenDTO: Decodable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var mandantId: FlexibleID?
}

/// Colour object used by Urlaub types and treatment types: `{ base: "#rrggbb", ... }`.
struct FarbeDTO: Decodable, Hashable, Sendable {
    var base: String?
}
