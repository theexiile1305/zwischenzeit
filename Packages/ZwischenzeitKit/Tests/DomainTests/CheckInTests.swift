import Domain
import Foundation
import Testing

@Suite struct CheckInTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func appt(_ status: Appointment.Status, kind: Appointment.Kind = .treatment) -> Appointment {
        Appointment(id: AppointmentID("a"), kind: kind, status: status, start: start,
                    end: start.addingTimeInterval(30 * 60), services: [])
    }

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test func arrivedIsWaitingFromShortlyBeforeStartUntilTheEnd() {
        #expect(appt(.arrived).checkIn(now: at(-30)) == .arrived)
        #expect(appt(.arrived).checkIn(now: at(-15)) == .waiting)
        #expect(appt(.arrived).checkIn(now: at(10)) == .waiting)
        #expect(appt(.arrived).checkIn(now: at(30)) == .arrived)
    }

    @Test func notCheckedInIsOverdueAFewMinutesAfterStart() {
        #expect(appt(.planned).checkIn(now: at(4)) == .none)
        #expect(appt(.planned).checkIn(now: at(5)) == .overdue)
        #expect(appt(.planned).checkIn(now: at(30)) == .none)
    }

    @Test func cancelledAndBlockersHaveNoCheckIn() {
        #expect(appt(.cancelled).checkIn(now: at(10)) == .none)
        #expect(appt(.arrived, kind: .blocker).checkIn(now: at(10)) == .none)
    }

    @Test func legacyDoneStatusDecodesAsArrived() throws {
        let decoded = try JSONDecoder().decode([Appointment.Status].self, from: Data(#"["done","arrived","planned"]"#.utf8))
        #expect(decoded == [.arrived, .arrived, .planned])
    }
}

@Suite struct TextSnippetTests {
    @Test func appendsWithASpaceAfterAWord() {
        let r = SnippetInsertion.insert("Gut vertragen.", into: "KG durchgeführt.", replacing: nil)
        #expect(r.text == "KG durchgeführt. Gut vertragen.")
        #expect(r.cursor == r.text.count)
    }

    @Test func noExtraSpaceIntoEmptyTextOrAfterNewline() {
        #expect(SnippetInsertion.insert("A.", into: "", replacing: nil).text == "A.")
        #expect(SnippetInsertion.insert("A.", into: "X\n", replacing: nil).text == "X\nA.")
    }

    @Test func insertsAtTheCursorAndReplacesTheSelection() {
        let r = SnippetInsertion.insert("gut", into: "Heute schlecht vertragen", replacing: 6..<14)
        #expect(r.text == "Heute gut vertragen")
        #expect(r.cursor == 9)
        let mid = SnippetInsertion.insert("sehr", into: "Heutegut", replacing: 5..<5)
        #expect(mid.text == "Heute sehr gut")
        #expect(mid.cursor == 10)
    }

    @Test func placeholdersExpandWithoutPatientData() {
        let start = PracticeCalendar.date(on: Date(timeIntervalSince1970: 1_791_900_000), hour: 9, minute: 0)
        let a = Appointment(id: AppointmentID("a"), kind: .treatment, status: .planned, start: start,
                            end: start.addingTimeInterval(1200), sessionNumber: 6, sessionsTotal: 10, services: [])
        let text = TextSnippet(title: "x", body: "Behandlung {behandlung} am {datum}.").expanded(for: a)
        #expect(text == "Behandlung 6/10 am \(PracticeCalendar.format(start, "ddMMyyyy")).")
        #expect(!text.contains("{"))
    }
}
