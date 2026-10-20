import Foundation

/// `rest/Termine/?date=yyyy-MM-dd` and `rest/Termine/{id}` → `{ termine: [...], mitarbeiterTermine: [...] }`
/// (the detail call returns one item in `termine` and no `mitarbeiterTermine`).
struct TermineDayDTO: Decodable, Sendable {
    var termine: [TerminDTO]?
    var mitarbeiterTermine: [MitarbeiterTerminDTO]?
}

/// One appointment. A Termin is a run of `leistungen` back to back from `uhrzeit`,
/// each with its own duration, employee, room and Terminart. All times are
/// "yyyy-MM-dd HH:mm" wall-clock Europe/Berlin.
struct TerminDTO: Decodable, Sendable {
    struct Ref: Decodable, Hashable, Sendable {
        var id: FlexibleID?
        var name: String?
    }

    struct Kunde: Decodable, Sendable {
        var id: FlexibleID?
        var vorname: String?
        var name: String?
    }

    struct Rezept: Decodable, Sendable {
        var id: FlexibleID?
        var belegNummer: String?
    }

    struct Terminart: Decodable, Sendable {
        var id: FlexibleID?
        var name: String?
        var leistungsArt: String?       // "STANDARD", "HAUSBESUCH", "PASSIV"
        var farbe: FarbeDTO?
    }

    struct Leistung: Decodable, Sendable {
        var id: FlexibleID?
        var dauer: FlexibleInt?
        var mitarbeiter: Ref?
        var raum: Ref?
        var terminart: Terminart?
        var rezeptIndex: FlexibleInt?   // 0-based
        var rezeptCount: FlexibleInt?
    }

    struct Dokumentation: Decodable, Sendable {
        var text: String?
    }

    struct Gruppe: Decodable, Sendable {
        var id: FlexibleID?
    }

    var id: FlexibleID
    var datum: String?
    var uhrzeit: String?
    var kunde: Kunde?
    var rezept: Rezept?
    var leistungen: [Leistung]?
    var gruppenTermin: Gruppe?
    var dauerTermin: Ref?
    var terminSerieIndex: FlexibleInt?  // 0-based
    var terminSerieCount: FlexibleInt?
    var abgesagtAm: String?
    var abgesagtDurchMandantAm: String?
    var wahrgenommen: Bool?             // nil = not yet recorded, false = no-show
    var dokumentation: Dokumentation?
    var trash: Bool?                    // soft-deleted
}

/// Working-time window of one employee on that day. The gaps in between are not bookable.
struct MitarbeiterTerminDTO: Decodable, Sendable {
    var datum: String?
    var von: String?
    var bis: String?
    var mitarbeiter: TerminDTO.Ref?
}
