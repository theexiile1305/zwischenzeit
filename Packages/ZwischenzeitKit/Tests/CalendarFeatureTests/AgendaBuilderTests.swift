import Domain
import Foundation
import Testing
@testable import CalendarFeature

private let cal = PracticeCalendar.self
private let monday = cal.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!

private func appt(_ id: String, _ h: Int, _ m: Int, minutes: Int, status: Appointment.Status = .planned,
                  n: Int? = nil, of total: Int? = nil) -> Appointment {
    let start = cal.date(on: monday, hour: h, minute: m)
    return Appointment(id: AppointmentID(id), kind: .treatment, status: status, start: start,
                       end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                       sessionNumber: n, sessionsTotal: total, services: [])
}

private func band(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> BlockedInterval {
    BlockedInterval(start: cal.date(on: monday, hour: h1, minute: m1), end: cal.date(on: monday, hour: h2, minute: m2))
}

private func kinds(_ entries: [AgendaEntry]) -> [String] {
    entries.map {
        switch $0.kind {
        case .appointment(let a): a.id.raw
        case .free(let m): "free\(m)"
        case .pause: "pause"
        }
    }
}

@Suite struct AgendaBuilderTests {
    @Test func gapsOfTenMinutesOrMoreAreShown() {
        let e = AgendaBuilder.entries([appt("a", 8, 0, minutes: 20), appt("b", 8, 25, minutes: 20), appt("c", 9, 0, minutes: 20)],
                                      blocked: [], on: monday)
        #expect(kinds(e) == ["a", "b", "free15", "c"])
    }

    @Test func bandsInsideTheDayBecomePausesAndOffDutyIsIgnored() {
        let e = AgendaBuilder.entries([appt("a", 11, 40, minutes: 20), appt("b", 12, 30, minutes: 20)],
                                      blocked: [band(0, 0, 8, 0), band(12, 0, 12, 30), band(18, 0, 23, 59)], on: monday)
        #expect(kinds(e) == ["a", "pause", "b"])
        #expect(AgendaBuilder.summary(e).pause?.duration == TimeInterval(30 * 60))
    }

    @Test func cancelledSlotCountsAsFree() {
        let e = AgendaBuilder.entries([appt("a", 8, 0, minutes: 20), appt("x", 8, 20, minutes: 20, status: .cancelled),
                                       appt("b", 8, 40, minutes: 20)], blocked: [], on: monday)
        #expect(kinds(e) == ["a", "free20", "x", "b"])
        let s = AgendaBuilder.summary(e)
        #expect(s.treatments == 2 && s.cancelled == 1 && s.bookedMinutes == 40)
    }

    @Test func overlappingGroupDoesNotProduceGaps() {
        let e = AgendaBuilder.entries([appt("a", 11, 0, minutes: 60), appt("b", 11, 0, minutes: 60), appt("c", 12, 0, minutes: 20)],
                                      blocked: [], on: monday)
        #expect(kinds(e) == ["a", "b", "c"])
    }

    @Test func longestLongGapIsThePauseWhenNoBand() {
        let e = AgendaBuilder.entries([appt("a", 8, 0, minutes: 20), appt("b", 9, 0, minutes: 20), appt("c", 12, 0, minutes: 20)],
                                      blocked: [], on: monday)
        let s = AgendaBuilder.summary(e)
        #expect(s.pause.map { cal.time($0.start) } == "09:20")
        #expect(s.text == "3 Termine · 08:00–12:20 · Pause 09:20–12:00")
    }

    @Test func nextUpIsRunningOrNextTreatment() {
        let list = [appt("a", 8, 0, minutes: 30, status: .arrived), appt("b", 8, 30, minutes: 30),
                    appt("x", 9, 0, minutes: 20, status: .cancelled), appt("c", 9, 20, minutes: 20)]
        #expect(AgendaBuilder.nextUp(list, now: cal.date(on: monday, hour: 8, minute: 40))?.id.raw == "b")
        #expect(AgendaBuilder.nextUp(list, now: cal.date(on: monday, hour: 9, minute: 0))?.id.raw == "c")
        #expect(AgendaBuilder.nextUp(list, now: cal.date(on: monday, hour: 10, minute: 0)) == nil)
    }

    @Test func summaryCountsCheckedInPatients() {
        let list = [appt("a", 8, 0, minutes: 30, status: .arrived), appt("b", 8, 30, minutes: 30, status: .arrived),
                    appt("x", 9, 0, minutes: 20, status: .cancelled), appt("c", 9, 20, minutes: 20)]
        let s = AgendaBuilder.summary(AgendaBuilder.entries(list, blocked: [], on: monday))
        #expect(s.arrived == 2)
        #expect(s.treatments == 3)
    }

    @Test func firstAndLastSession() {
        #expect(appt("a", 8, 0, minutes: 20, n: 6, of: 6).isLastSession)
        #expect(appt("a", 8, 0, minutes: 20, n: 1, of: 6).isFirstSession)
        #expect(!appt("a", 8, 0, minutes: 20).isLastSession)
    }
}
