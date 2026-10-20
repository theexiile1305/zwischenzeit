import Domain
import Foundation

/// `TToolsAPI` against the ttools.app backend (`https://www.ttools.app/ttools/rest/…`).
/// Read-only except the documentation text (`saveDocumentation`); the other non-GET calls are
/// login, MFA, token revalidation and logout.
public actor LiveTToolsAPI: TToolsAPI {
    public static let defaultBaseURL = URL(string: "https://www.ttools.app/ttools/")!

    private let http: HTTPClient
    private let store: any TokenStorage
    private let now: @Sendable () -> Date

    /// Practice typed at login, kept until MFA finishes.
    private var pendingPractice: String?
    /// Temporary token from a 202 login; only valid for `rest/mfa`.
    private var mfaToken: String?

    private var cachedEmployees: [Employee]?
    private var cachedRooms: [Room]?
    private var cachedTreatmentTypes: [TreatmentType]?
    /// One request per day serves the calendar and the watch sync.
    private var dayCache: [Date: (fetched: Date, value: TermineDayDTO)] = [:]
    private static let dayCacheTTL: TimeInterval = 60

    public init(baseURL: URL = defaultBaseURL, session: URLSession = SecureSession.make(),
                store: any TokenStorage = KeychainTokenStore(), now: @escaping @Sendable () -> Date = { .now }) {
        self.http = HTTPClient(baseURL: baseURL, session: session, store: store)
        self.store = store
        self.now = now
    }

    // MARK: Auth

    public func signIn(practice: String, username: String, password: String) async throws -> SignInResult {
        resetCaches()
        mfaToken = nil
        let body = try JSONEncoder().encode(["principal": "\(practice)_\(username)", "password": password])
        let response = try await http.send(method: "POST", path: "rest/login", body: body)
        // A wrong password is a 401 or 403 here, not "missing permission".
        if response.status == 401 || response.status == 403 { throw APIError.unauthorized }
        try HTTPClient.check(response.status)
        let dto = try decodeTokens(response.data)
        guard let access = dto.accessToken else { throw APIError.unauthorized }
        if response.status == 202 {
            pendingPractice = practice
            mfaToken = access
            return .mfaRequired
        }
        return .signedIn(try await startSession(dto, practice: practice))
    }

    public func submitMFA(code: String) async throws -> Session {
        guard let mfaToken else { throw APIError.unauthorized }
        let body = try JSONEncoder().encode(["code": code])
        let response = try await http.send(method: "POST", path: "rest/mfa", body: body, bearer: mfaToken)
        switch response.status {
        case 200..<300: break
        case 401: throw APIError.mfaInvalid
        default:
            self.mfaToken = nil
            try HTTPClient.check(response.status)
        }
        self.mfaToken = nil
        return try await startSession(try decodeTokens(response.data), practice: pendingPractice ?? "")
    }

    public func restoreSession() async throws -> Session? {
        guard let tokens = store.load() else { return nil }
        do {
            return try await session(practice: tokens.practice ?? "")
        } catch APIError.unauthorized {
            store.clear()
            return nil
        }
    }

    public func signOut() async {
        if let token = store.load()?.accessToken {
            _ = try? await http.send(method: "POST", path: "rest/logout", body: Data("{}".utf8), bearer: token)
        }
        store.clear()
        resetCaches()
    }

    private func startSession(_ dto: TokenDTO, practice: String) async throws -> Session {
        guard let access = dto.accessToken else { throw APIError.unauthorized }
        store.save(Tokens(accessToken: access, refreshToken: dto.refreshToken, mandantId: dto.mandantId?.raw, practice: practice))
        do {
            return try await session(practice: practice)
        } catch {
            store.clear()
            throw error
        }
    }

    /// The token says which Mitarbeiter the user is; their calendar opens by default.
    private func session(practice: String) async throws -> Session {
        guard let access = store.load()?.accessToken else { throw APIError.unauthorized }
        let claims = try TokenClaims(jwt: access)
        guard let id = claims.mitarbeiter else { throw APIError.noLinkedEmployee }
        let me: MitarbeiterDTO = try await http.get("rest/mitarbeiter/\(id.raw)")
        return Session(employee: Mapping.employee(me), practiceName: practice)
    }

    private func decodeTokens(_ data: Data) throws -> TokenDTO {
        // The MFA endpoint has been seen answering with a JSON string instead of an object.
        if let dto = try? JSONDecoder().decode(TokenDTO.self, from: data) { return dto }
        if let s = try? JSONDecoder().decode(String.self, from: data),
           let dto = try? JSONDecoder().decode(TokenDTO.self, from: Data(s.utf8)) { return dto }
        throw APIError.server(status: 0)
    }

    private func resetCaches() {
        cachedEmployees = nil
        cachedRooms = nil
        cachedTreatmentTypes = nil
        dayCache = [:]
    }

    // MARK: Reference data

    public func employees() async throws -> [Employee] {
        if let cachedEmployees { return cachedEmployees }
        let list: [MitarbeiterDTO] = try await http.get("rest/Stammdaten/entities/Mitarbeiter")
        let employees = list.filter(\.isActive).map(Mapping.employee)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        cachedEmployees = employees
        return employees
    }

    /// Reference lists are nice-to-have: the calendar still works without them.
    public func rooms() async throws -> [Room] {
        if let cachedRooms { return cachedRooms }
        let table = try? await http.get("rest/Stammdaten/Raum", as: StammdatenTableDTO<RaumDTO>.self)
        let rooms = (table?.data ?? []).map { Room(id: RoomID($0.id.raw), name: $0.name ?? "") }
        cachedRooms = rooms
        return rooms
    }

    public func treatmentTypes() async throws -> [TreatmentType] {
        if let cachedTreatmentTypes { return cachedTreatmentTypes }
        let table = try? await http.get("rest/Stammdaten/Terminart", as: StammdatenTableDTO<TerminartDTO>.self)
        let types = (table?.data ?? []).map(Mapping.treatmentType)
        cachedTreatmentTypes = types
        return types
    }

    // MARK: Calendar

    public func appointments(for employee: EmployeeID, in range: DateInterval) async throws -> [Appointment] {
        let raw = try await days(in: range).flatMap { $0.1.termine ?? [] }
        let mapped = raw.compactMap(Mapping.appointment)
        let mine = mapped.filter { a in a.services.contains { $0.employeeID == employee } && a.start < range.end && a.end > range.start }
        let staff = Set(mapped.flatMap { $0.services.map(\.employeeID) })
        let noEmployee = mapped.filter { $0.services.contains { $0.employeeID.raw.isEmpty } }.count
        liveLog.info("appointments: \(raw.count) termine, \(mapped.count) mapped, \(mine.count) for employee; \(staff.count) employees in data, own id present: \(staff.contains(employee)), own id length \(employee.raw.count), without employee: \(noEmployee)")
        return mine.sorted { ($0.start, $0.id.raw) < ($1.start, $1.id.raw) }
    }

    /// Absences plus the time outside the employee's working windows.
    public func blockedIntervals(for employee: EmployeeID, in range: DateInterval) async throws -> [BlockedInterval] {
        async let absences: [UrlaubDTO] = http.get("rest/mitarbeiter/urlaub/\(employee.raw)", query: [
            URLQueryItem(name: "datumVon", value: Mapping.dayFormatter.string(from: range.start)),
            URLQueryItem(name: "datumBis", value: Mapping.dayFormatter.string(from: range.end.addingTimeInterval(-1))),
        ])
        let outsideHours = try await days(in: range).flatMap { day, dto in
            Mapping.blocked(windows: dto.mitarbeiterTermine ?? [], employee: employee, day: day)
        }
        return (try await absences.compactMap(Mapping.blocked) + outsideHours)
            .filter { $0.start < range.end && $0.end > range.start }
            .sorted { $0.start < $1.start }
    }

    /// Fetches each day of `range` (in parallel), served from a short cache.
    private func days(in range: DateInterval) async throws -> [(Date, TermineDayDTO)] {
        var day = PracticeCalendar.startOfDay(range.start)
        var wanted: [Date] = []
        while day < range.end {
            wanted.append(day)
            day = PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        let t = now()
        let missing = wanted.filter { d in dayCache[d].map { t.timeIntervalSince($0.fetched) > Self.dayCacheTTL } ?? true }
        let http = self.http
        let fetched = try await withThrowingTaskGroup(of: (Date, TermineDayDTO).self) { group in
            for d in missing {
                group.addTask {
                    let dto: TermineDayDTO = try await http.get("rest/Termine/", query: [
                        URLQueryItem(name: "date", value: Mapping.dayFormatter.string(from: d)),
                    ])
                    return (d, dto)
                }
            }
            return try await group.reduce(into: [(Date, TermineDayDTO)]()) { $0.append($1) }
        }
        for (d, dto) in fetched { dayCache[d] = (t, dto) }
        return wanted.compactMap { d in dayCache[d].map { (d, $0.value) } }
    }

    // MARK: Detail

    public func appointmentDetail(_ id: AppointmentID) async throws -> AppointmentDetail {
        let dto: TermineDayDTO = try await http.get("rest/Termine/\(id.raw)")
        guard let t = dto.termine?.first, let appointment = Mapping.appointment(t) else { throw APIError.notFound }
        var prescriptions: [Prescription] = []
        if let patient = appointment.patient,
           let overview = try? await http.get("rest/Kunden/uebersicht/\(patient.id.raw)", as: KundenUebersichtDTO.self) {
            let all = (overview.rezepte ?? []).map { Mapping.prescription($0, patient: patient.id) }
            prescriptions = all.filter { $0.id == appointment.prescriptionID } + all.filter { $0.id != appointment.prescriptionID }
        }
        return AppointmentDetail(appointment: appointment, prescriptions: prescriptions,
                                 documentation: t.dokumentation?.text ?? "")
    }

    // MARK: Write (the one exception to read-only)

    /// The backend has no documentation endpoint: like the PWA, this sends the whole Termin back
    /// with `PUT rest/Termine`. To lose nothing the DTOs don't decode, the Termin is fetched as raw
    /// JSON right before, only `dokumentation.text` is changed, and every other field goes back as read.
    public func saveDocumentation(_ text: String, for id: AppointmentID, replacing previous: String) async throws -> AppointmentDetail {
        let raw = try await http.authorized(method: "GET", path: "rest/Termine/\(id.raw)")
        let body = try Self.documentationUpdate(raw, id: id, text: text, previous: previous)
        _ = try await http.authorized(method: "PUT", path: "rest/Termine", body: body)
        dayCache = [:]
        liveLog.info("documentation saved, \(text.count) characters")
        return try await appointmentDetail(id)
    }

    /// The PUT body: the fetched Termin with only `dokumentation.text` replaced. Pure, unit-tested.
    static func documentationUpdate(_ raw: Data, id: AppointmentID, text: String, previous: String) throws -> Data {
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              var termin = (root["termine"] as? [[String: Any]])?.first,
              FlexibleID.string(termin["id"]) == id.raw else { throw APIError.notFound }
        // Freitext blockers keep their text in the same field; they are not documentation.
        guard termin["kunde"] is [String: Any] else { throw APIError.forbidden }
        var doku = termin["dokumentation"] as? [String: Any] ?? [:]
        let current = doku["text"] as? String ?? ""
        guard current == previous else { throw DocumentationConflict(current: current) }
        doku["text"] = text
        termin["dokumentation"] = doku
        return try JSONSerialization.data(withJSONObject: termin)
    }
}
