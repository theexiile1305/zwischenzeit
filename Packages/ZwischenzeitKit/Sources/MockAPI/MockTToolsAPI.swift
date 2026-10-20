import Domain
import Foundation

/// In-memory stand-in for the TTools backend. Fake people only,
/// never real patient data.
public actor MockTToolsAPI: TToolsAPI {
    public enum Failure: Sendable { case none, offline, unauthorized }

    public var latency: Duration
    public var failure: Failure = .none

    private var session: Session?
    private var pendingMFA = false
    private let seed: MockSeed
    private let appointmentsByID: [AppointmentID: Appointment]
    private let now: Date
    /// Documentation saved in this run. Lost on relaunch, like any mock data.
    private var savedDocumentation: [AppointmentID: String] = [:]

    public init(now: Date = .now, latency: Duration = .milliseconds(300), signedIn: Bool = true) {
        let seed = MockSeed(now: now)
        self.seed = seed
        self.now = now
        self.latency = latency
        self.appointmentsByID = Dictionary(uniqueKeysWithValues: seed.appointments.map { ($0.id, $0) })
        self.session = signedIn ? Session(employee: seed.employees[0], practiceName: "Praxis Beispiel") : nil
    }

    public func setFailure(_ failure: Failure) { self.failure = failure }

    // MARK: Auth

    /// Password "mfa" asks for a second factor; the mock accepts code "000000".
    public func signIn(practice: String, username: String, password: String) async throws -> SignInResult {
        try await simulate(requiresSession: false)
        guard !practice.isEmpty, !username.isEmpty, !password.isEmpty else { throw APIError.unauthorized }
        if password == "mfa" { pendingMFA = true; return .mfaRequired }
        return .signedIn(startSession())
    }

    public func submitMFA(code: String) async throws -> Session {
        try await simulate(requiresSession: false)
        guard pendingMFA else { throw APIError.unauthorized }
        guard code == "000000" else { throw APIError.mfaInvalid }
        pendingMFA = false
        return startSession()
    }

    private func startSession() -> Session {
        let s = Session(employee: seed.employees[0], practiceName: "Praxis Beispiel")
        session = s
        return s
    }

    public func restoreSession() async throws -> Session? {
        try await simulate(requiresSession: false)
        return session
    }

    public func signOut() async { session = nil }

    // MARK: Reference data

    public func employees() async throws -> [Employee] { try await simulate(); return seed.employees }
    public func rooms() async throws -> [Room] { try await simulate(); return seed.rooms }
    public func treatmentTypes() async throws -> [TreatmentType] { try await simulate(); return seed.treatmentTypes }

    // MARK: Calendar

    public func appointments(for employee: EmployeeID, in range: DateInterval) async throws -> [Appointment] {
        try await simulate()
        return appointmentsByID.values
            .filter { $0.services.contains { $0.employeeID == employee } && $0.start < range.end && $0.end > range.start }
            .sorted { ($0.start, $0.id.raw) < ($1.start, $1.id.raw) }
    }

    public func blockedIntervals(for employee: EmployeeID, in range: DateInterval) async throws -> [BlockedInterval] {
        try await simulate()
        return seed.blocked(for: employee, in: range)
    }

    // MARK: Detail

    public func appointmentDetail(_ id: AppointmentID) async throws -> AppointmentDetail {
        try await simulate()
        guard let a = appointmentsByID[id] else { throw APIError.notFound }
        let prescriptions = a.patient.map { p in seed.prescriptions.filter { $0.patientID == p.id } } ?? []
        let linkedFirst = prescriptions.filter { $0.id == a.prescriptionID } + prescriptions.filter { $0.id != a.prescriptionID }
        let documentation = savedDocumentation[id]
            ?? (a.status == .arrived && a.end < now ? "Behandlung wie geplant durchgeführt, gut vertragen." : "")
        return AppointmentDetail(appointment: a, prescriptions: linkedFirst, documentation: documentation)
    }

    public func saveDocumentation(_ text: String, for id: AppointmentID, replacing previous: String) async throws -> AppointmentDetail {
        try await simulate()
        guard appointmentsByID[id]?.kind == .treatment else { throw APIError.notFound }
        let current = try await appointmentDetail(id).documentation
        guard current == previous else { throw DocumentationConflict(current: current) }
        savedDocumentation[id] = text
        return try await appointmentDetail(id)
    }

    // MARK: Helpers

    private func simulate(requiresSession: Bool = true) async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        switch failure {
        case .none: break
        case .offline: throw APIError.offline
        case .unauthorized: session = nil; throw APIError.unauthorized
        }
        if requiresSession && session == nil { throw APIError.unauthorized }
    }
}
