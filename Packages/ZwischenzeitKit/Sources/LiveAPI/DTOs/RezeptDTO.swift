import Foundation

/// `rest/Kunden/uebersicht/{kundeId}` → `{ kunde, rezepte, vertragsDaten }`; only the prescriptions are read.
struct KundenUebersichtDTO: Decodable, Sendable {
    var rezepte: [RezeptDTO]?
}

struct RezeptDTO: Decodable, Sendable {
    struct Position: Decodable, Sendable { var anzahl: FlexibleInt? }

    var id: FlexibleID
    var belegNummer: String?
    var rezeptStatus: FlexibleInt?     // 0 in Behandlung, 1 abgebrochen, 2/3 abgeschlossen, 4 abgerechnet
    var heilmittelLeistung: [Position]?
}
