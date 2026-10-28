import Domain
import Foundation
import Testing
@testable import WatchSync

private let cal = PracticeCalendar.self
private let day = cal.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
private func at(_ h: Int, _ m: Int) -> Date { cal.date(on: day, hour: h, minute: m) }

private let reference = ReferenceData(
    employees: [Employee(id: EmployeeID("e1"), displayName: "Lena Sommer", initials: "LS")],
    rooms: [Room(id: RoomID("r1"), name: "Raum 1")],
    treatmentTypes: [TreatmentType(id: TreatmentTypeID("kg"), name: "Krankengymnastik", category: .kg, defaultDurationMinutes: 20, maxGroupSize: 1)])

private func appt(_ id: String, _ h: Int, _ m: Int, minutes: Int = 20, status: Appointment.Status = .planned) -> Appointment {
    Appointment(id: AppointmentID(id), kind: .treatment, status: status, start: at(h, m), end: at(h, m).addingTimeInterval(TimeInterval(minutes * 60)),
                patient: Patient(id: PatientID("p"), firstName: "Anna", lastName: "Bergmann"),
                services: [AppointmentService(id: "s", treatmentTypeID: TreatmentTypeID("kg"), employeeID: EmployeeID("e1"), roomID: RoomID("r1"), durationMinutes: minutes)])
}

private func item(_ id: String, _ h: Int, _ m: Int, minutes: Int = 20, cancelled: Bool = false) -> UpcomingItem {
    UpcomingItem(id: id, start: at(h, m), end: at(h, m).addingTimeInterval(TimeInterval(minutes * 60)), title: id, style: .kg, isCancelled: cancelled)
}

@Suite struct UpcomingBuilderTests {
    @Test func disabledSendsNothing() {
        let p = UpcomingBuilder.build([appt("a", 10, 0)], reference: reference, settings: WatchSettings(isEnabled: false), now: at(9, 0))
        #expect(p.items.isEmpty)
        #expect(!p.settings.isEnabled)
    }

    @Test func initialsNeverLeakTheFullName() throws {
        let p = UpcomingBuilder.build([appt("a", 10, 0)], reference: reference, settings: WatchSettings(isEnabled: true, nameDisplay: .initials), now: at(9, 0))
        #expect(p.items.first?.title == "A. B.")
        let json = String(decoding: try UpcomingPayload.encode(p), as: UTF8.self)
        #expect(!json.contains("Bergmann"))
        #expect(!json.contains("Anna"))
    }

    @Test func hiddenNameShowsTreatmentAsTitle() {
        let p = UpcomingBuilder.build([appt("a", 10, 0)], reference: reference, settings: WatchSettings(isEnabled: true, nameDisplay: .hidden), now: at(9, 0))
        #expect(p.items.first?.title == "Krankengymnastik")
        #expect(p.items.first?.subtitle == nil)
    }

    @Test func roomAndTreatmentFollowToggles() {
        let s = WatchSettings(isEnabled: true, nameDisplay: .full, showTreatment: false, showRoom: false)
        let p = UpcomingBuilder.build([appt("a", 10, 0)], reference: reference, settings: s, now: at(9, 0))
        #expect(p.items.first?.title == "Anna Bergmann")
        #expect(p.items.first?.subtitle == nil)
        #expect(p.items.first?.room == nil)
    }

    @Test func endedAppointmentsAreDroppedAndListIsCapped() {
        let many = (0..<60).map { appt("a\($0)", 8, 0, minutes: 10 + $0) } + [appt("past", 7, 0, minutes: 20)]
        let p = UpcomingBuilder.build(many, reference: reference, settings: WatchSettings(isEnabled: true), now: at(8, 5))
        #expect(p.items.count == UpcomingPayload.maxItems)
        #expect(!p.items.contains { $0.id == "past" })
    }

    @Test func payloadRoundTripsThroughJSON() throws {
        let p = UpcomingBuilder.build([appt("a", 10, 0)], reference: reference, settings: WatchSettings(isEnabled: true), now: at(9, 0))
        #expect(try UpcomingPayload.decode(UpcomingPayload.encode(p)) == p)
    }

    @Test func sessionIsSentEvenWithHiddenNames() {
        var a = appt("a", 10, 0)
        a.sessionNumber = 6
        a.sessionsTotal = 6
        let p = UpcomingBuilder.build([a], reference: reference, settings: WatchSettings(isEnabled: true, nameDisplay: .hidden), now: at(9, 0))
        #expect(p.items.first?.session == "6/6")
        #expect(p.items.first?.isLastSession == true)
    }

    @Test func payloadFromOlderPhoneStillDecodes() throws {
        // Written before `session`, `isLastSession` and `isCheckedIn` existed.
        let json = #"{"generatedAt":0,"settings":{"isEnabled":true,"leadMinutes":10,"nameDisplay":"initials","showTreatment":true,"showRoom":true,"haptic":true},"items":[{"id":"a","start":100,"end":200,"title":"A. B.","style":"kg","isCancelled":false}]}"#
        let p = try UpcomingPayload.decode(Data(json.utf8))
        #expect(p.items.first?.session == nil)
        #expect(p.items.first?.isLastSession == false)
        #expect(p.items.first?.isCheckedIn == false)
    }

    @Test func checkInIsSent() {
        var a = appt("a", 10, 0)
        a.status = .arrived
        let p = UpcomingBuilder.build([a, appt("b", 11, 0)], reference: reference, settings: WatchSettings(isEnabled: true), now: at(9, 0))
        #expect(p.items.map(\.isCheckedIn) == [true, false])
    }
}

@Suite struct NotificationPlannerTests {
    private func payload(_ items: [UpcomingItem], lead: Int = 10) -> UpcomingPayload {
        UpcomingPayload(generatedAt: at(7, 0), settings: WatchSettings(isEnabled: true, leadMinutes: lead), items: items)
    }

    @Test func firesLeadMinutesBeforeStart() {
        let plan = NotificationPlanner.plan(payload([item("a", 10, 0)]), now: at(9, 0))
        #expect(plan.map(\.fireDate) == [at(9, 50)])
    }

    @Test func zeroLeadFiresAtStart() {
        let plan = NotificationPlanner.plan(payload([item("a", 10, 0)], lead: 0), now: at(9, 0))
        #expect(plan.map(\.fireDate) == [at(10, 0)])
    }

    @Test func backToBackFiresWhenThePreviousEnds() {
        // a 9:40–10:00, b 10:05 with 10 min lead → b would fire 9:55 during a → fire at 10:00 instead.
        let plan = NotificationPlanner.plan(payload([item("a", 9, 40), item("b", 10, 5)]), now: at(9, 0))
        #expect(plan.map(\.fireDate) == [at(9, 30), at(10, 0)])
    }

    @Test func cancelledAndPastAreSkipped() {
        let plan = NotificationPlanner.plan(payload([item("past", 9, 5), item("x", 11, 0, cancelled: true), item("b", 12, 0)]), now: at(9, 0))
        #expect(plan.map(\.item.id) == ["b"])
    }

    @Test func capsPendingNotifications() {
        let items = (0..<30).map { item("i\($0)", 10, 0, minutes: 5).with(start: at(10, 0).addingTimeInterval(TimeInterval($0 * 600))) }
        #expect(NotificationPlanner.plan(payload(items), now: at(9, 0)).count == NotificationPlanner.maxPending)
    }

    @Test func disabledPlansNothing() {
        var p = payload([item("a", 10, 0)])
        p.settings.isEnabled = false
        #expect(NotificationPlanner.plan(p, now: at(9, 0)).isEmpty)
    }
}

@Suite struct WidgetTimelineTests {
    @Test func flipsToTheNextAppointmentWhenOneEnds() {
        let p = UpcomingPayload(generatedAt: at(7, 0), settings: WatchSettings(isEnabled: true),
                                items: [item("a", 9, 0), item("x", 9, 30, cancelled: true), item("b", 10, 0)])
        let entries = WidgetTimelinePlanner.entries(p, now: at(8, 0))
        #expect(entries.map(\.date) == [at(8, 0), at(9, 20), at(10, 20)])
        #expect(entries.map { $0.next?.id } == ["a", "b", nil])
    }

    @Test func staleAfterTwoHours() {
        let p = UpcomingPayload(generatedAt: at(7, 0), settings: WatchSettings(isEnabled: true), items: [])
        #expect(!p.isStale(at: at(8, 59)))
        #expect(p.isStale(at: at(9, 1)))
    }

    @Test func unreadableRetriesSoonerThanMissingOrLoaded() {
        let now = at(9, 0)
        let unreadable = WidgetTimelinePlanner.nextReloadDate(for: .unreadable, now: now)
        let missing = WidgetTimelinePlanner.nextReloadDate(for: .missing, now: now)
        let corrupt = WidgetTimelinePlanner.nextReloadDate(for: .corrupt, now: now)
        let loaded = WidgetTimelinePlanner.nextReloadDate(for: .loaded(UpcomingPayload(generatedAt: now, settings: WatchSettings(isEnabled: true), items: [])), now: now)
        #expect(unreadable > now && unreadable < missing)
        #expect(unreadable < loaded)
        #expect(missing == corrupt)
    }
}

@Suite struct UpcomingStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }

    @Test func missingWhenNoFileExists() {
        #expect(UpcomingStore.loadResult(at: tempURL()) == .missing)
    }

    @Test func unreadableWhenFileCannotBeRead() throws {
        let url = tempURL()
        FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        #expect(UpcomingStore.loadResult(at: url) == .unreadable)
    }

    @Test func corruptWhenJSONIsGarbage() throws {
        let url = tempURL()
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(UpcomingStore.loadResult(at: url) == .corrupt)
    }

    @Test func loadedWhenPayloadDecodes() throws {
        let url = tempURL()
        let payload = UpcomingPayload.disabled(at: Date(timeIntervalSince1970: 0))
        try UpcomingStore.save(payload, at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(UpcomingStore.loadResult(at: url) == .loaded(payload))
    }

    /// Disabling writes clear() then save(). If the re-save fails, the file must stay
    /// absent (.missing) rather than leaving the previous, enabled payload on disk.
    @Test func clearBeforeFailedSaveLeavesMissingNotStale() throws {
        let url = tempURL()
        let enabled = UpcomingPayload(generatedAt: Date(timeIntervalSince1970: 0), settings: WatchSettings(isEnabled: true), items: [])
        try UpcomingStore.save(enabled, at: url)
        UpcomingStore.clear(at: url)
        #expect(UpcomingStore.loadResult(at: url) == .missing)
    }
}

private extension UpcomingItem {
    func with(start: Date) -> UpcomingItem {
        var c = self
        let d = end.timeIntervalSince(self.start)
        c.start = start
        c.end = start.addingTimeInterval(d)
        return c
    }
}

@Suite struct NotificationContentTests {
    private func plannedItem(title: String = "A. B.", subtitle: String? = "Krankengymnastik", room: String? = "Raum 1") -> UpcomingItem {
        UpcomingItem(id: "a1", start: at(10, 0), end: at(10, 20), title: title, subtitle: subtitle, room: room, style: .kg)
    }

    @Test func titleCountsDownOrSaysNow() {
        #expect(NotificationContent.title(for: plannedItem(), leadMinutes: 10) == "In 10 Min.: 10:00")
        #expect(NotificationContent.title(for: plannedItem(), leadMinutes: 0) == "Jetzt: 10:00")
    }

    @Test func bodyJoinsOnlyWhatThePhoneSent() {
        #expect(NotificationContent.body(for: plannedItem()) == "A. B. · Krankengymnastik · Raum 1")
        #expect(NotificationContent.body(for: plannedItem(subtitle: nil, room: nil)) == "A. B.")
    }

    @Test func userInfoCarriesOnlyTheID() {
        let info = NotificationContent.userInfo(for: plannedItem(title: "Anna Bergmann"))
        #expect(info == [NotificationContent.itemIDKey: "a1"])
    }
}
