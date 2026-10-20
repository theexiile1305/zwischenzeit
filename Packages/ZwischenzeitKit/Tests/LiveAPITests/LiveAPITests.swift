import Domain
import Foundation
import Testing
@testable import LiveAPI

private let day = PracticeCalendar.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
private let base = URL(string: "https://example.test/ttools/")!
private let me = json(["id": 7, "vorname": "Anna", "name": "Hartmann", "status": "AKTIV"])

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!)
}

private func api(_ store: InMemoryTokenStore) -> LiveTToolsAPI {
    LiveTToolsAPI(baseURL: base, session: StubProtocol.session(), store: store, now: { day })
}

/// Serialized: the stub's handler is global.
@Suite(.serialized) struct LiveAPITests {
    // MARK: Mapping

    @Test func mapsADayOfTermine() throws {
        let dto = try JSONDecoder().decode(TermineDayDTO.self, from: try fixture("termine-day"))
        let all = (dto.termine ?? []).compactMap(Mapping.appointment)
        #expect(all.map(\.id.raw) == ["t101", "t102", "t103", "t104", "t105"]) // t106 is trashed

        let kg = try #require(all.first { $0.id.raw == "t101" })
        #expect(kg.kind == .treatment && kg.status == .planned)
        #expect(kg.start == PracticeCalendar.date(on: day, hour: 8, minute: 40))
        #expect(kg.end == PracticeCalendar.date(on: day, hour: 9, minute: 10)) // 20 + 10 minutes back to back
        #expect(kg.patient?.listName == "Bergmann, Anna")
        #expect(kg.sessionNumber == 3 && kg.sessionsTotal == 6)                 // rezeptIndex is 0-based
        #expect(kg.prescriptionID?.raw == "r900")
        #expect(kg.services.map(\.treatmentTypeID.raw) == ["ta12", "ta20"])
        #expect(kg.services.first?.employeeID.raw == "m7" && kg.services.first?.roomID?.raw == "raum1")
        #expect(kg.services.last?.roomID == nil)

        let cancelled = try #require(all.first { $0.id.raw == "t102" })
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.seriesID?.raw == "d8")
        #expect(cancelled.sessionNumber == 4 && cancelled.sessionsTotal == 10)  // falls back to the series counter

        let blocker = try #require(all.first { $0.id.raw == "t103" })
        #expect(blocker.kind == .blocker && blocker.note == "Teambesprechung")
        #expect(blocker.sessionNumber == nil)

        #expect(all.first { $0.id.raw == "t104" }?.status == .arrived)
        #expect(all.first { $0.id.raw == "t105" }?.status == .cancelled)       // no-show
    }

    @Test func gapsBetweenWorkingWindowsAreBlocked() throws {
        let dto = try JSONDecoder().decode(TermineDayDTO.self, from: try fixture("termine-day"))
        let windows = dto.mitarbeiterTermine ?? []
        let at = { (h: Int, m: Int) in PracticeCalendar.date(on: day, hour: h, minute: m) }
        let next = PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: day)!
        #expect(Mapping.blocked(windows: windows, employee: EmployeeID("m7"), day: day) == [
            BlockedInterval(start: day, end: at(8, 0)),
            BlockedInterval(start: at(12, 0), end: at(13, 0)),
            BlockedInterval(start: at(17, 30), end: next),
        ])
        // No window for this employee while others have one: the whole day is off.
        #expect(Mapping.blocked(windows: windows, employee: EmployeeID("m1"), day: day) == [BlockedInterval(start: day, end: next)])
        // The practice keeps no working times that day: nothing is blocked.
        #expect(Mapping.blocked(windows: [], employee: EmployeeID("m7"), day: day).isEmpty)
    }

    @Test func absenceWithTimesBlocksOnlyThatSpan() throws {
        let u = UrlaubDTO(id: nil, datum: "2026-10-14 00:00", von: "2026-10-14 13:00", bis: "2026-10-14 15:30", urlaubArt: nil)
        let b = try #require(Mapping.blocked(u))
        #expect(b.start == PracticeCalendar.date(on: day, hour: 13, minute: 0))
        #expect(b.end == PracticeCalendar.date(on: day, hour: 15, minute: 30))
        let whole = try #require(Mapping.blocked(UrlaubDTO(id: nil, datum: "2026-10-14 00:00", von: nil, bis: nil, urlaubArt: nil)))
        #expect(whole.start == day && whole.end == PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: day)!)
    }

    @Test func mapsReferenceData() throws {
        let types = try JSONDecoder().decode(StammdatenTableDTO<TerminartDTO>.self, from: try fixture("stammdaten-terminart"))
            .data.map(Mapping.treatmentType)
        #expect(types.map(\.category) == [.kg, .mldLong, .device, .heat])
        #expect(types.first?.defaultDurationMinutes == 20 && types.first?.shortCode == "KG")
        let staff = try JSONDecoder().decode([MitarbeiterDTO].self, from: try fixture("stammdaten-mitarbeiter"))
        #expect(staff.filter(\.isActive).map(Mapping.employee).map(\.displayName) == ["L. Hartmann", "T. Abel"])
        #expect(Mapping.employee(staff[0]).initials == "LH" && Mapping.employee(staff[1]).initials == "TA")
    }

    // MARK: Auth

    @Test func signInStoresTokensAndLoadsEmployee() async throws {
        let access = jwt(["mitarbeiter": 7, "roles": ["user"]])
        StubProtocol.reset { r in
            switch r.url!.path {
            case "/ttools/rest/login":
                let body = try! JSONSerialization.jsonObject(with: r.httpBody!) as! [String: String]
                #expect(body["principal"] == "praxis_anna")
                return (200, json(["accessToken": access, "refreshToken": "R1", "mandantId": 3]))
            case "/ttools/rest/mitarbeiter/7": return (200, me)
            default: return (404, Data())
            }
        }
        let store = InMemoryTokenStore()
        guard case .signedIn(let s) = try await api(store).signIn(practice: "praxis", username: "anna", password: "pw") else {
            Issue.record("expected signedIn"); return
        }
        #expect(s.employee.id.raw == "7" && s.employee.displayName == "A. Hartmann" && s.practiceName == "praxis")
        #expect(store.load() == Tokens(accessToken: access, refreshToken: "R1", mandantId: "3", practice: "praxis"))
    }

    @Test func wrongPasswordIsUnauthorized() async throws {
        StubProtocol.reset { _ in (401, Data()) }
        await #expect(throws: APIError.unauthorized) {
            try await api(InMemoryTokenStore()).signIn(practice: "p", username: "u", password: "x")
        }
    }

    @Test func mfaFlow() async throws {
        let access = jwt(["mitarbeiter": 7])
        StubProtocol.reset { r in
            switch r.url!.path {
            case "/ttools/rest/login": return (202, json(["accessToken": "TEMP"]))
            case "/ttools/rest/mfa":
                #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer TEMP")
                let code = (try! JSONSerialization.jsonObject(with: r.httpBody!) as! [String: String])["code"]
                // The real endpoint sometimes answers with a JSON-encoded string.
                return code == "123456" ? (200, try! JSONEncoder().encode(String(data: json(["accessToken": access, "refreshToken": "R"]), encoding: .utf8)!)) : (401, Data())
            case "/ttools/rest/mitarbeiter/7": return (200, me)
            default: return (404, Data())
            }
        }
        let store = InMemoryTokenStore()
        let live = api(store)
        guard case .mfaRequired = try await live.signIn(practice: "p", username: "u", password: "pw") else {
            Issue.record("expected mfaRequired"); return
        }
        #expect(store.load() == nil)
        await #expect(throws: APIError.mfaInvalid) { try await live.submitMFA(code: "000000") }
        let s = try await live.submitMFA(code: "123456")
        #expect(s.employee.id.raw == "7")
        #expect(store.load()?.accessToken == access)
    }

    @Test(arguments: [(423, APIError.locked), (429, APIError.rateLimited)])
    func mfaLockoutErrors(status: Int, expected: APIError) async throws {
        StubProtocol.reset { r in r.url!.path.hasSuffix("login") ? (202, json(["accessToken": "TEMP"])) : (status, Data()) }
        let live = api(InMemoryTokenStore())
        _ = try await live.signIn(practice: "p", username: "u", password: "pw")
        await #expect(throws: expected) { try await live.submitMFA(code: "1") }
    }

    @Test func userWithoutMitarbeiterCannotSignIn() async throws {
        StubProtocol.reset { _ in (200, json(["accessToken": jwt(["roles": ["admin"]]), "refreshToken": "R"])) }
        let store = InMemoryTokenStore()
        await #expect(throws: APIError.noLinkedEmployee) {
            try await api(store).signIn(practice: "p", username: "u", password: "pw")
        }
        #expect(store.load() == nil)
    }

    // MARK: Token refresh

    @Test func concurrent401sShareOneRevalidate() async throws {
        let old = jwt(["mitarbeiter": 7, "v": 1]), new = jwt(["mitarbeiter": 7, "v": 2])
        StubProtocol.reset { r in
            let auth = r.value(forHTTPHeaderField: "Authorization")
            if r.url!.path.hasSuffix("revalidate") {
                #expect(r.value(forHTTPHeaderField: "Refresh-Token") == "R1")
                return (200, json(["accessToken": new]))
            }
            guard auth == "Bearer \(new)" else { return (401, Data()) }
            return (200, json(["termine": [], "mitarbeiterTermine": []]))
        }
        let store = InMemoryTokenStore(Tokens(accessToken: old, refreshToken: "R1"))
        let week = DateInterval(start: day, duration: 7 * 86_400)
        _ = try await api(store).appointments(for: EmployeeID("7"), in: week)
        #expect(StubProtocol.paths().filter { $0.hasSuffix("revalidate") }.count == 1)
        #expect(store.load()?.accessToken == new && store.load()?.refreshToken == "R1")
    }

    @Test func failedRevalidateSignsOut() async throws {
        StubProtocol.reset { _ in (401, Data()) }
        let store = InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": 7]), refreshToken: "R1"))
        await #expect(throws: APIError.unauthorized) { try await api(store).employees() }
        #expect(store.load() == nil)
    }

    @Test func restoreSessionWithExpiredRefreshReturnsNil() async throws {
        StubProtocol.reset { _ in (401, Data()) }
        let store = InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": 7]), refreshToken: "R1"))
        #expect(try await api(store).restoreSession() == nil)
    }

    // MARK: Calendar

    @Test func detailPutsLinkedPrescriptionFirst() async throws {
        let day = try JSONSerialization.jsonObject(with: try fixture("termine-day")) as! [String: Any]
        let one = json(["termine": [(day["termine"] as! [Any])[0]]])
        let overview = try fixture("kunden-uebersicht")
        StubProtocol.reset { r in
            switch r.url!.path {
            case "/ttools/rest/Termine/t101": return (200, one)
            case "/ttools/rest/Kunden/uebersicht/k55": return (200, overview)
            default: return (404, Data())
            }
        }
        let d = try await api(InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": "m7"]), refreshToken: "R")))
            .appointmentDetail(AppointmentID("t101"))
        #expect(d.prescriptions.map(\.id.raw) == ["r900", "r800"])
        #expect(d.prescriptions[0].status == .open && d.prescriptions[0].sessionsTotal == 12)
        #expect(d.prescriptions[1].status == .completed)
        #expect(d.documentation == "")
    }

    @Test func appointmentsFetchEachDayOnceAndFilterByEmployee() async throws {
        let fixtureData = try fixture("termine-day")
        StubProtocol.reset { r in
            let date = URLComponents(url: r.url!, resolvingAgainstBaseURL: false)!.queryItems?.first { $0.name == "date" }?.value
            #expect(r.url!.absoluteString.hasPrefix("https://example.test/ttools/rest/Termine/?date="))
            return (200, date == "2026-10-14" ? fixtureData : json(["termine": []]))
        }
        let live = api(InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": "m7"]), refreshToken: "R")))
        let twoDays = DateInterval(start: day, end: PracticeCalendar.calendar.date(byAdding: .day, value: 2, to: day)!)
        let a = try await live.appointments(for: EmployeeID("m7"), in: twoDays)
        #expect(a.map(\.id.raw) == ["t101", "t102", "t105", "t103"])
        let b = try await live.appointments(for: EmployeeID("m9"), in: twoDays) // cached
        #expect(b.map(\.id.raw) == ["t104"])
        #expect(StubProtocol.paths().count == 2)
    }

    // MARK: Documentation write

    /// Synthetic Termin with fields the DTOs never decode; all of them must survive the PUT.
    private static var rawTermin: [String: Any] { [
        "id": 4711, "datum": "2026-10-14 08:40", "uhrzeit": "1970-01-01 08:40",
        "kunde": ["id": 55, "vorname": "Erika", "name": "Muster", "telefon": "0000"],
        "leistungen": [["id": 1, "dauer": 20, "mitarbeiter": ["id": 7, "name": "A. Hartmann"], "abrechnung": ["betrag": 21.37, "zuzahlung": true]]],
        "wahrgenommen": NSNull(), "abrechnungsStatus": "OFFEN", "version": 12,
        "dokumentation": ["id": 99, "text": "alt", "trash": false],
    ] }

    private static func detailJSON(_ termin: [String: Any]) -> Data { json(["termine": [termin]]) }

    @Test func documentationUpdateChangesOnlyTheText() throws {
        let body = try LiveTToolsAPI.documentationUpdate(Self.detailJSON(Self.rawTermin), id: AppointmentID("4711"),
                                                         text: "neu", previous: "alt")
        var sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let doku = try #require(sent.removeValue(forKey: "dokumentation") as? [String: Any])
        #expect(doku["text"] as? String == "neu")
        #expect(doku["id"] as? Int == 99 && doku["trash"] as? Bool == false)
        var expected = Self.rawTermin
        expected.removeValue(forKey: "dokumentation")
        #expect(NSDictionary(dictionary: sent) == NSDictionary(dictionary: expected))
    }

    @Test func documentationUpdateRefusesConflictsAndBlockers() throws {
        #expect(throws: DocumentationConflict(current: "alt")) {
            try LiveTToolsAPI.documentationUpdate(Self.detailJSON(Self.rawTermin), id: AppointmentID("4711"), text: "x", previous: "")
        }
        var blocker = Self.rawTermin
        blocker.removeValue(forKey: "kunde")
        #expect(throws: APIError.forbidden) {
            try LiveTToolsAPI.documentationUpdate(Self.detailJSON(blocker), id: AppointmentID("4711"), text: "x", previous: "alt")
        }
        #expect(throws: APIError.notFound) {
            try LiveTToolsAPI.documentationUpdate(Self.detailJSON(Self.rawTermin), id: AppointmentID("1"), text: "x", previous: "alt")
        }
        var empty = Self.rawTermin
        empty.removeValue(forKey: "dokumentation")
        let body = try LiveTToolsAPI.documentationUpdate(Self.detailJSON(empty), id: AppointmentID("4711"), text: "erste", previous: "")
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect((sent?["dokumentation"] as? [String: Any])?["text"] as? String == "erste")
    }

    @Test func saveDocumentationPutsTheWholeTerminThenReloads() async throws {
        let saved = LockedBox(Self.rawTermin)
        StubProtocol.reset { r in
            switch (r.httpMethod, r.url!.path) {
            case ("GET", "/ttools/rest/Termine/4711"): return (200, Self.detailJSON(saved.value))
            case ("PUT", "/ttools/rest/Termine"):
                saved.value = try! JSONSerialization.jsonObject(with: r.httpBody!) as! [String: Any]
                return (200, r.httpBody!)
            default: return (404, Data())
            }
        }
        let live = api(InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": 7]), refreshToken: "R")))
        let detail = try await live.saveDocumentation("Behandlung gut vertragen.", for: AppointmentID("4711"), replacing: "alt")
        #expect(detail.documentation == "Behandlung gut vertragen.")
        let calls = StubProtocol.lock.withLock { StubProtocol.requests.map { "\($0.httpMethod!) \($0.url!.path)" } }
        #expect(calls.prefix(3) == ["GET /ttools/rest/Termine/4711", "PUT /ttools/rest/Termine", "GET /ttools/rest/Termine/4711"])
        let put = StubProtocol.lock.withLock { StubProtocol.requests[1] }
        #expect(put.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func expiredTokenDuringSaveResendsTheSameBody() async throws {
        let old = jwt(["mitarbeiter": 7, "n": 1]), fresh = jwt(["mitarbeiter": 7, "n": 2])
        StubProtocol.reset { r in
            if r.url!.path.hasSuffix("revalidate") { return (200, json(["accessToken": fresh, "refreshToken": "R2"])) }
            if r.httpMethod == "PUT", r.value(forHTTPHeaderField: "Authorization") == "Bearer \(old)" { return (401, Data()) }
            return r.httpMethod == "PUT" ? (200, Data("{}".utf8)) : (200, Self.detailJSON(Self.rawTermin))
        }
        let live = api(InMemoryTokenStore(Tokens(accessToken: old, refreshToken: "R1")))
        _ = try await live.saveDocumentation("neu", for: AppointmentID("4711"), replacing: "alt")
        let puts = StubProtocol.lock.withLock { StubProtocol.requests.filter { $0.httpMethod == "PUT" } }
        #expect(puts.count == 2)
        #expect(puts[0].httpBody == puts[1].httpBody && puts[0].httpBody?.isEmpty == false)
    }

    @Test func saveDocumentationSendsNothingOnConflict() async throws {
        StubProtocol.reset { r in
            r.httpMethod == "GET" ? (200, Self.detailJSON(Self.rawTermin)) : (500, Data())
        }
        let live = api(InMemoryTokenStore(Tokens(accessToken: jwt(["mitarbeiter": 7]), refreshToken: "R")))
        await #expect(throws: DocumentationConflict(current: "alt")) {
            try await live.saveDocumentation("x", for: AppointmentID("4711"), replacing: "")
        }
        #expect(StubProtocol.lock.withLock { StubProtocol.requests.allSatisfy { $0.httpMethod == "GET" } })
    }
}

/// Mutable state shared with the stub handler.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
