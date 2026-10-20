import Foundation

/// A Textbaustein for the documentation editor. Generic text only, never patient data,
/// so it may be stored on the device.
public struct TextSnippet: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String                // chip label, "Wie geplant"
    public var body: String                 // inserted text, may hold placeholders

    public init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }

    /// Placeholders filled in at insert time. Deliberately no patient name.
    public static let placeholders: [(token: String, help: String)] = [
        ("{datum}", "Datum des Termins, 14.10.2026"),
        ("{behandlung}", "Behandlung n/m, 6/10"),
    ]

    public func expanded(for appointment: Appointment) -> String {
        body.replacingOccurrences(of: "{datum}", with: PracticeCalendar.format(appointment.start, "ddMMyyyy"))
            .replacingOccurrences(of: "{behandlung}", with: appointment.sessionLabel ?? "")
    }

    public static let defaults: [TextSnippet] = [
        TextSnippet(title: "MLD30", body: "MLD 30 durchgefühert"),
        TextSnippet(title: "TRXP", body: "TRX Plank"),
        TextSnippet(title: "TRXS", body: "TRX Squats"),
        TextSnippet(title: "WTT", body: "WTT Schulter-/Nackenbereich"),
        TextSnippet(title: "Befund", body: "Befund"),
        TextSnippet(title: "BBrot", body: "BBrot 10kg"),
    ]
}

/// Where a snippet lands in the text, and where the cursor goes after it. Offsets are in
/// `Character`s. Pure, unit-tested.
public enum SnippetInsertion {
    /// Replaces `range` (or appends when nil) with `snippet`. Adds a space before it when it
    /// would glue onto a word, and one after when text follows directly.
    public static func insert(_ snippet: String, into text: String, replacing range: Range<Int>?) -> (text: String, cursor: Int) {
        let count = text.count
        let lower = min(max(range?.lowerBound ?? count, 0), count)
        let upper = min(max(range?.upperBound ?? count, lower), count)
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        let before = text[..<start]
        let after = text[end...]
        var piece = snippet
        if let last = before.last, !last.isWhitespace { piece = " " + piece }
        if let first = after.first, !first.isWhitespace { piece += " " }
        let cursor = lower + piece.count - (after.first.map { !$0.isWhitespace } == true ? 1 : 0)
        return (String(before) + piece + String(after), cursor)
    }
}
