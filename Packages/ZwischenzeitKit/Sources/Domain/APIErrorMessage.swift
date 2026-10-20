import Foundation

extension APIError {
    /// Short German message for banners.
    public var message: String {
        switch self {
        case .unauthorized: "Sitzung abgelaufen. Bitte erneut anmelden."
        case .forbidden: "Dafür fehlt die Berechtigung."
        case .notFound: "Der Termin wurde nicht gefunden."
        case .offline: "Keine Verbindung. Angezeigt wird der letzte Stand."
        case .server(let status): "Serverfehler (\(status)). Bitte später erneut versuchen."
        case .mfaInvalid: "Ungültiger Code."
        case .locked: "Account gesperrt."
        case .rateLimited: "Zu viele Fehlversuche. Bitte später erneut versuchen."
        case .noLinkedEmployee: "Diesem Benutzer ist kein Mitarbeiter zugeordnet. Bitte in der TTools Web-App verknüpfen."
        }
    }
}
