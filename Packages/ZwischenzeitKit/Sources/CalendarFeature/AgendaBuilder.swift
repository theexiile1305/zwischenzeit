import Domain
import Foundation

/// One row of the "Heute" agenda.
public struct AgendaEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case appointment(Appointment)
        /// Unbooked time between two appointments.
        case free(minutes: Int)
        /// A not-bookable band inside the working day (usually the lunch break).
        case pause
    }

    public let id: String
    public var start: Date
    public var end: Date
    public var kind: Kind

    public var appointment: Appointment? {
        if case .appointment(let a) = kind { return a }
        return nil
    }
}

/// The line under the date: "9 Termine · 08:00–16:40 · Pause 12:00–12:30".
public struct AgendaSummary: Equatable, Sendable {
    public var treatments: Int
    public var arrived: Int           // checked in at reception
    public var cancelled: Int
    public var firstStart: Date?
    public var lastEnd: Date?
    public var pause: DateInterval?
    public var bookedMinutes: Int
}

/// Pure layout of one day as a list. Unit-tested in `AgendaBuilderTests`.
public enum AgendaBuilder {
    /// Gaps shorter than this are not shown.
    public static let minimumGap = 10
    /// A gap this long counts as the pause when no band covers it.
    public static let minimumPause = 30

    public static func entries(_ appointments: [Appointment], blocked: [BlockedInterval], on day: Date) -> [AgendaEntry] {
        let dayAppointments = appointments
            .filter { PracticeCalendar.calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { ($0.start, $0.id.raw) < ($1.start, $1.id.raw) }
        let active = dayAppointments.filter { $0.status != .cancelled }
        var out = dayAppointments.map { AgendaEntry(id: $0.id.raw, start: $0.start, end: $0.end, kind: .appointment($0)) }

        guard let windowStart = active.map(\.start).min(), let windowEnd = active.map(\.end).max() else { return out }

        // Bands strictly inside the working window, clipped to it.
        let pauses = blocked.compactMap { b -> DateInterval? in
            let s = max(b.start, windowStart), e = min(b.end, windowEnd)
            return e > s ? DateInterval(start: s, end: e) : nil
        }
        let busy = pauses.filter { pause in !active.contains { $0.start < pause.end && $0.end > pause.start } }
        out += busy.map { AgendaEntry(id: "pause-\(Int($0.start.timeIntervalSince1970))", start: $0.start, end: $0.end, kind: .pause) }

        // Free gaps: walk the occupied intervals in start order.
        let occupied = (active.map { DateInterval(start: $0.start, end: $0.end) } + busy).sorted { $0.start < $1.start }
        var cursor = windowStart
        for interval in occupied {
            let minutes = Int(interval.start.timeIntervalSince(cursor) / 60)
            if minutes >= minimumGap {
                out.append(AgendaEntry(id: "free-\(Int(cursor.timeIntervalSince1970))", start: cursor, end: interval.start,
                                       kind: .free(minutes: minutes)))
            }
            cursor = max(cursor, interval.end)
        }

        return out.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return rank(lhs) < rank(rhs)
        }
    }

    /// At equal start: free and pause rows come before the appointment (a cancelled
    /// appointment's slot shows "frei" first), then by id for a stable order.
    private static func rank(_ e: AgendaEntry) -> String {
        switch e.kind {
        case .free: "0"
        case .pause: "1"
        case .appointment(let a): "2\(a.id.raw)"
        }
    }

    public static func summary(_ entries: [AgendaEntry]) -> AgendaSummary {
        let appointments = entries.compactMap(\.appointment)
        let treatments = appointments.filter { $0.kind == .treatment }
        let active = appointments.filter { $0.status != .cancelled }
        let pause = entries.first { $0.kind == .pause }.map { DateInterval(start: $0.start, end: $0.end) }
            ?? entries.filter {
                if case .free(let m) = $0.kind { return m >= minimumPause }
                return false
            }.max { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }
            .map { DateInterval(start: $0.start, end: $0.end) }
        return AgendaSummary(
            treatments: treatments.filter { $0.status != .cancelled }.count,
            arrived: treatments.filter { $0.status == .arrived }.count,
            cancelled: treatments.filter { $0.status == .cancelled }.count,
            firstStart: active.map(\.start).min(),
            lastEnd: active.map(\.end).max(),
            pause: pause,
            bookedMinutes: treatments.filter { $0.status != .cancelled }.reduce(0) { $0 + $1.durationMinutes })
    }

    /// The patient to think about now: the running treatment, else the next one today.
    public static func nextUp(_ appointments: [Appointment], now: Date) -> Appointment? {
        appointments
            .filter { $0.kind == .treatment && $0.status != .cancelled && $0.end > now
                && PracticeCalendar.calendar.isDate($0.start, inSameDayAs: now) }
            .min { ($0.start, $0.id.raw) < ($1.start, $1.id.raw) }
    }
}

extension AgendaSummary {
    /// "9 Termine · 08:00–16:40 · Pause 12:00–12:30"
    public var text: String {
        var parts = [treatments == 1 ? "1 Termin" : "\(treatments) Termine"]
        if let firstStart, let lastEnd { parts.append("\(PracticeCalendar.time(firstStart))–\(PracticeCalendar.time(lastEnd))") }
        if let pause { parts.append("Pause \(PracticeCalendar.time(pause.start))–\(PracticeCalendar.time(pause.end))") }
        return parts.joined(separator: " · ")
    }
}
