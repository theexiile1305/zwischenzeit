import Foundation

/// `rest/Stammdaten/entities/Mitarbeiter` (all) and `rest/mitarbeiter/{id}` (one).
struct MitarbeiterDTO: Decodable, Hashable, Sendable {
    var id: FlexibleID
    var vorname: String?
    var name: String?
    var kuerzel: String?
    var status: String?

    var isActive: Bool { status != "INAKTIV" }
}

/// `rest/mitarbeiter/urlaub/{id}?datumVon=&datumBis=`: absences, times as "yyyy-MM-dd HH:mm".
/// Whole days unless `von`/`bis` are set.
struct UrlaubDTO: Decodable, Sendable {
    struct Art: Decodable, Sendable { var name: String? }

    var id: FlexibleID?
    var datum: String
    var von: String?
    var bis: String?
    var urlaubArt: Art?
}
