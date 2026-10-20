import Foundation

/// `rest/Stammdaten/{Klasse}` → `{ data: [...], columns: [...] }` (columns are table UI, ignored).
struct StammdatenTableDTO<Row: Decodable & Sendable>: Decodable, Sendable {
    var data: [Row]
}

/// `rest/Stammdaten/Terminart`: treatment types.
struct TerminartDTO: Decodable, Sendable {
    var id: FlexibleID
    var name: String?
    var kurzName: String?
    var takt: FlexibleInt?             // default duration in minutes
    var leistungsArt: String?
}

/// `rest/Stammdaten/Raum`.
struct RaumDTO: Decodable, Sendable {
    var id: FlexibleID
    var name: String?
}
