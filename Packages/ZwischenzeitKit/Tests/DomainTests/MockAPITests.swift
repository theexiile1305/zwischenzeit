import Domain
import Foundation
import Testing
@testable import MockAPI

private let now = PracticeCalendar.date(on: PracticeCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!, hour: 9, minute: 0)

@Suite struct MockAPITests {
    @Test func seedIsDeterministicAndCoversEveryVariant() async throws {
        let a = MockTToolsAPI(now: now, latency: .zero)
        let b = MockTToolsAPI(now: now, latency: .zero)
        let week = DateInterval(start: PracticeCalendar.startOfWeek(now), duration: 7 * 86_400)
        let x = try await a.appointments(for: EmployeeID("e1"), in: week)
        let y = try await b.appointments(for: EmployeeID("e1"), in: week)
        #expect(x == y)
        #expect(x.count > 40)
        #expect(x.contains { $0.kind == .blocker })
        #expect(x.contains { $0.groupID != nil })
        #expect(x.contains { $0.seriesID != nil })
        #expect(x.contains { $0.status == .cancelled })
        #expect(x.contains { $0.status == .arrived })
    }

    @Test func detailLinksPrescriptionFirst() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        let week = DateInterval(start: PracticeCalendar.startOfWeek(now), duration: 7 * 86_400)
        let a = try await api.appointments(for: EmployeeID("e1"), in: week).first { $0.kind == .treatment }!
        let detail = try await api.appointmentDetail(a.id)
        #expect(detail.prescriptions.first?.id == a.prescriptionID)
    }

    @Test func unknownIDIsNotFound() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        await #expect(throws: APIError.notFound) { try await api.appointmentDetail(AppointmentID("nope")) }
    }

    @Test func offlineFailureSurfaces() async throws {
        let api = MockTToolsAPI(now: now, latency: .zero)
        await api.setFailure(.offline)
        await #expect(throws: APIError.offline) { try await api.employees() }
    }
}
