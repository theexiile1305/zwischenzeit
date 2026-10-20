import Domain
import Foundation

/// Where one appointment sits inside a day column. Pure data, so it is unit-testable.
public struct PlacedEvent: Equatable, Sendable {
    public let id: AppointmentID
    /// Minutes from the top of the grid (grid starts at `dayStartHour`).
    public let top: Int
    /// Duration in minutes, at least `minMinutes`.
    public let height: Int
    public let column: Int
    public let columnCount: Int
}

public enum DayLayout {
    /// Packs overlapping appointments side by side.
    ///
    /// Appointments that overlap (directly or through a chain) form a cluster.
    /// Inside a cluster each one gets the leftmost free column, and the whole
    /// cluster shares the same column count so widths line up.
    public static func place(_ appointments: [Appointment], dayStartHour: Int, minMinutes: Int = 10) -> [PlacedEvent] {
        let sorted = appointments.sorted {
            ($0.start, $1.end, $0.id.raw) < ($1.start, $0.end, $1.id.raw)
        }
        var result: [PlacedEvent] = []
        var cluster: [(Appointment, Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            for (a, column) in cluster {
                let top = PracticeCalendar.minuteOfDay(a.start) - dayStartHour * 60
                let minutes = Int(a.end.timeIntervalSince(a.start) / 60)
                result.append(PlacedEvent(id: a.id, top: top, height: max(minutes, minMinutes), column: column, columnCount: count))
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for a in sorted {
            if a.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= a.start }) {
                columnEnds[free] = a.end
                cluster.append((a, free))
            } else {
                columnEnds.append(a.end)
                cluster.append((a, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, a.end)
        }
        flush()
        return result
    }

    /// Splits appointments by the practice-calendar day they start on.
    public static func byDay(_ appointments: [Appointment], days: [Date]) -> [Date: [Appointment]] {
        var out: [Date: [Appointment]] = Dictionary(uniqueKeysWithValues: days.map { ($0, []) })
        for a in appointments {
            let day = PracticeCalendar.startOfDay(a.start)
            if out[day] != nil { out[day]!.append(a) }
        }
        return out
    }

    /// Clamps a blocked interval to one day's grid, in grid minutes.
    public static func band(_ interval: BlockedInterval, on day: Date, dayStartHour: Int, dayEndHour: Int) -> ClosedRange<Int>? {
        let gridStart = PracticeCalendar.date(on: day, hour: dayStartHour, minute: 0)
        let gridEnd = PracticeCalendar.date(on: day, hour: dayEndHour, minute: 0)
        let s = max(interval.start, gridStart)
        let e = min(interval.end, gridEnd)
        guard s < e else { return nil }
        let top = PracticeCalendar.minuteOfDay(s) - dayStartHour * 60
        let bottom = e == gridEnd ? (dayEndHour - dayStartHour) * 60 : PracticeCalendar.minuteOfDay(e) - dayStartHour * 60
        return top...bottom
    }
}
