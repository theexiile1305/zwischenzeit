import Domain
import Foundation
import MockAPI
import Testing
@testable import CalendarFeature

private let cal = PracticeCalendar.self
private func day(_ d: Int, month: Int = 10) -> Date { cal.calendar.date(from: DateComponents(year: 2026, month: month, day: d))! }
private func dom(_ date: Date) -> Int { cal.calendar.component(.day, from: date) }

@MainActor
private func model(today: Int = 14, mode: CalendarMode = .week, limit: Int? = nil) -> CalendarModel {
    let now = cal.date(on: day(today), hour: 9, minute: 28)
    let m = CalendarModel(api: MockTToolsAPI(now: now, latency: .zero), employeeID: EmployeeID("e1"), reference: ReferenceData(), now: { now })
    m.weekDayLimit = limit
    m.mode = mode
    return m
}

@MainActor
@Suite struct CalendarModelTests {
    @Test func weekShowsMondayToFriday() {
        let m = model()
        #expect(m.days.map(dom) == [12, 13, 14, 15, 16])
    }

    @Test func compactWeekShowsThreeDaysFromAnchor() {
        #expect(model(limit: 3).days.map(dom) == [14, 15, 16])
    }

    @Test func compactWindowSkipsTheWeekend() {
        #expect(model(today: 16, limit: 3).days.map(dom) == [16, 19, 20])
    }

    @Test func compactStepMovesByThreeVisibleDays() {
        let m = model(limit: 3)
        m.step(1)
        #expect(dom(m.anchor) == 19)
        m.step(-1)
        #expect(dom(m.anchor) == 14)
    }

    @Test func dayStepSkipsWeekendUnlessShown() {
        let m = model(today: 16, mode: .day)
        m.step(1)
        #expect(dom(m.anchor) == 19)
        m.showWeekend = true
        m.go(to: day(16))
        m.step(1)
        #expect(dom(m.anchor) == 17)
    }

    @Test func stepWeekFallsBackToFridayWhenWeekendHidden() {
        let m = model(mode: .day)
        m.go(to: day(17)) // Saturday
        m.stepWeek(1)
        #expect(dom(m.anchor) == 23)
    }

    @Test func monthRangeCoversSpilloverWeeks() {
        let m = model(mode: .month)
        #expect(m.range.start == day(28, month: 9))
        #expect(m.range.end >= day(30))
    }

    @Test func weekAroundTheDSTChangeHasFiveDays() {
        let m = model(today: 26) // CET started Sun 25 Oct 2026
        #expect(m.days.map(dom) == [26, 27, 28, 29, 30])
    }
}
