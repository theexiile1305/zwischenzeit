import Domain
import Foundation
import Testing
@testable import CalendarFeature

private let cal = PracticeCalendar.self
private let monday = cal.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!

private func appt(_ id: String, _ h: Int, _ m: Int, minutes: Int, day: Date = monday) -> Appointment {
    let start = cal.date(on: day, hour: h, minute: m)
    return Appointment(id: AppointmentID(id), kind: .treatment, status: .planned, start: start,
                       end: start.addingTimeInterval(TimeInterval(minutes * 60)), services: [])
}

@Suite struct DayLayoutTests {
    @Test func openMinutesSubtractsBlockedTimeOnce() {
        func blocked(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> BlockedInterval {
            BlockedInterval(start: cal.date(on: monday, hour: h1, minute: m1), end: cal.date(on: monday, hour: h2, minute: m2))
        }
        // 07-20 is 780 min. Lunch 12:00-13:00 and an overlapping 12:30-13:30 absence cover 90 min, the evening 18:00-24:00 covers 120.
        let open = DayLayout.openMinutes(
            blocked: [blocked(12, 0, 13, 0), blocked(12, 30, 13, 30), blocked(18, 0, 23, 59)], on: monday, startHour: 7, endHour: 20)
        #expect(open == 780 - 90 - 120)
    }

    @Test func separateAppointmentsGetFullWidth() {
        let placed = DayLayout.place([appt("a", 8, 0, minutes: 20), appt("b", 8, 20, minutes: 20)], dayStartHour: 7)
        #expect(placed.map(\.columnCount) == [1, 1])
        #expect(placed.map(\.top) == [60, 80])
        #expect(placed.map(\.height) == [20, 20])
    }

    @Test func groupOfThreeSitsSideBySide() {
        let placed = DayLayout.place([appt("a", 11, 0, minutes: 60), appt("b", 11, 0, minutes: 60), appt("c", 11, 0, minutes: 60)], dayStartHour: 7)
        #expect(Set(placed.map(\.column)) == [0, 1, 2])
        #expect(placed.allSatisfy { $0.columnCount == 3 })
    }

    @Test func chainedOverlapSharesColumnCountAndReusesColumns() {
        // a 9:00–10:00, b 9:30–10:30, c 10:00–10:20 → c reuses a's column, cluster has 2 columns
        let placed = DayLayout.place([appt("a", 9, 0, minutes: 60), appt("b", 9, 30, minutes: 60), appt("c", 10, 0, minutes: 20)], dayStartHour: 7)
        let byID = Dictionary(uniqueKeysWithValues: placed.map { ($0.id.raw, $0) })
        #expect(byID["a"]!.column == 0)
        #expect(byID["b"]!.column == 1)
        #expect(byID["c"]!.column == 0)
        #expect(placed.allSatisfy { $0.columnCount == 2 })
    }

    @Test func shortAppointmentsGetMinimumHeight() {
        let placed = DayLayout.place([appt("a", 9, 0, minutes: 5)], dayStartHour: 7, minMinutes: 10)
        #expect(placed[0].height == 10)
    }

    @Test func dstFallBackDayUsesWallClockTimes() {
        // 25 Oct 2026: clocks go back 03:00 → 02:00. A 09:00 appointment must still sit at 09:00.
        let sunday = cal.calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let placed = DayLayout.place([appt("a", 9, 0, minutes: 30, day: sunday)], dayStartHour: 7)
        #expect(placed[0].top == 120)
        #expect(placed[0].height == 30)
    }

    @Test func dstSpringForwardDayListsSevenDistinctDays() {
        let monday = cal.calendar.date(from: DateComponents(year: 2026, month: 3, day: 23))!
        let days = cal.days(from: monday, count: 7)
        #expect(Set(days.map { cal.calendar.component(.day, from: $0) }).count == 7)
        #expect(days.allSatisfy { cal.minuteOfDay($0) == 0 })
    }

    @Test func bandIsClampedToTheGrid() {
        let lunch = BlockedInterval(start: cal.date(on: monday, hour: 12, minute: 0), end: cal.date(on: monday, hour: 12, minute: 30))
        #expect(DayLayout.band(lunch, on: monday, dayStartHour: 7, dayEndHour: 20) == 300...330)
        let night = BlockedInterval(start: cal.date(on: monday, hour: 18, minute: 0), end: cal.calendar.date(byAdding: .day, value: 1, to: monday)!)
        #expect(DayLayout.band(night, on: monday, dayStartHour: 7, dayEndHour: 20) == 660...780)
    }
}
