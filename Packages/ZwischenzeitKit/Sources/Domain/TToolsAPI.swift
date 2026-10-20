import Foundation

// MARK: - IDs

public struct ID<Tag>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }
}

public typealias AppointmentID   = ID<Appointment>
public typealias EmployeeID      = ID<Employee>
public typealias PatientID       = ID<Patient>
public typealias PrescriptionID  = ID<Prescription>
public typealias RoomID          = ID<Room>
public typealias TreatmentTypeID = ID<TreatmentType>
public typealias SeriesID        = ID<AppointmentSeries>
public typealias GroupID         = ID<AppointmentGroup>

public enum AppointmentSeries {}
public enum AppointmentGroup {}

// MARK: - Reference data

public struct Employee: Identifiable, Hashable, Codable, Sendable {
    public let id: EmployeeID
    public var displayName: String          // "A. Hartmann" style in the drawer, full name in the chip
    public var initials: String

    public init(id: EmployeeID, displayName: String, initials: String) {
        self.id = id
        self.displayName = displayName
        self.initials = initials
    }
}

public struct Room: Identifiable, Hashable, Codable, Sendable {
    public let id: RoomID
    public var name: String

    public init(id: RoomID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Colour family of a treatment type. LiveTToolsAPI maps the server's data onto it.
public enum TreatmentCategory: String, Codable, Sendable, CaseIterable {
    case kg, mld, mldLong, device, heat, cold, other
}

public struct TreatmentType: Identifiable, Hashable, Codable, Sendable {
    public let id: TreatmentTypeID
    public var name: String                 // "Krankengymnastik", "Lymphdrainage Teil 30 Minuten", ...
    public var category: TreatmentCategory
    public var defaultDurationMinutes: Int
    public var maxGroupSize: Int            // 1 = individual, 3 = "KG-Gerät bis zu 3 Patienten"
    public var shortCode: String?           // "KGG" badge

    public init(id: TreatmentTypeID, name: String, category: TreatmentCategory, defaultDurationMinutes: Int, maxGroupSize: Int, shortCode: String? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultDurationMinutes = defaultDurationMinutes
        self.maxGroupSize = maxGroupSize
        self.shortCode = shortCode
    }
}

public struct Patient: Identifiable, Hashable, Codable, Sendable {
    public let id: PatientID
    public var firstName: String
    public var lastName: String

    public init(id: PatientID, firstName: String, lastName: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
    }
}

public struct Prescription: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable { case open, completed, cancelled, unknown }
    public let id: PrescriptionID
    public var patientID: PatientID
    public var number: String               // "R: 18216-9"
    public var sessionsTotal: Int           // the m in "n/m"
    public var status: Status

    public init(id: PrescriptionID, patientID: PatientID, number: String, sessionsTotal: Int, status: Status) {
        self.id = id
        self.patientID = patientID
        self.number = number
        self.sessionsTotal = sessionsTotal
        self.status = status
    }
}

/// Drives the gray "not bookable" bands in the grid.
public struct BlockedInterval: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

// MARK: - Appointments

public struct Appointment: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case treatment, blocker }
    /// `arrived`: reception ticked the patient in (`wahrgenommen == true`). It is set at
    /// check-in, before the treatment, so it does not mean "done".
    public enum Status: String, Codable, Sendable {
        case planned, arrived, cancelled

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // "done" is the pre-2026-10-19 name of `arrived`.
            self = raw == "done" ? .arrived : (Status(rawValue: raw) ?? .planned)
        }
    }

    public let id: AppointmentID
    public var kind: Kind
    public var status: Status
    public var start: Date
    public var end: Date
    public var patient: Patient?            // nil for blockers ("Freitext")
    public var prescriptionID: PrescriptionID?
    public var sessionNumber: Int?          // the n in "n/m"
    public var sessionsTotal: Int?          // the m in "n/m"
    public var seriesID: SeriesID?          // ∞ marker (dauerTerminId)
    public var groupID: GroupID?            // side-by-side group column (gruppenTerminId)
    public var services: [AppointmentService]
    public var note: String?                // blocker text, third card line ("MLD 30 durchgeführt")

    public init(id: AppointmentID, kind: Kind, status: Status, start: Date, end: Date, patient: Patient? = nil, prescriptionID: PrescriptionID? = nil, sessionNumber: Int? = nil, sessionsTotal: Int? = nil, seriesID: SeriesID? = nil, groupID: GroupID? = nil, services: [AppointmentService], note: String? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.start = start
        self.end = end
        self.patient = patient
        self.prescriptionID = prescriptionID
        self.sessionNumber = sessionNumber
        self.sessionsTotal = sessionsTotal
        self.seriesID = seriesID
        self.groupID = groupID
        self.services = services
        self.note = note
    }
}

public struct AppointmentService: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var treatmentTypeID: TreatmentTypeID
    public var employeeID: EmployeeID
    public var roomID: RoomID?
    public var durationMinutes: Int

    public init(id: String, treatmentTypeID: TreatmentTypeID, employeeID: EmployeeID, roomID: RoomID? = nil, durationMinutes: Int) {
        self.id = id
        self.treatmentTypeID = treatmentTypeID
        self.employeeID = employeeID
        self.roomID = roomID
        self.durationMinutes = durationMinutes
    }
}

/// Everything the detail screen shows.
public struct AppointmentDetail: Hashable, Codable, Sendable {
    public var appointment: Appointment
    public var prescriptions: [Prescription] // the carousel; first = linked one
    public var documentation: String

    public init(appointment: Appointment, prescriptions: [Prescription], documentation: String) {
        self.appointment = appointment
        self.prescriptions = prescriptions
        self.documentation = documentation
    }
}

// MARK: - Session

public struct Session: Codable, Sendable {
    public var employee: Employee            // whose calendar opens by default
    public var practiceName: String          // "Medisport Starnberg" in the drawer

    public init(employee: Employee, practiceName: String) {
        self.employee = employee
        self.practiceName = practiceName
    }
}

// MARK: - Errors

public enum APIError: Error, Equatable, Sendable {
    case unauthorized                         // → back to login, token cleared
    case forbidden
    case notFound
    case offline
    case server(status: Int)
    case mfaInvalid                           // wrong TOTP code, retry allowed
    case locked                               // account locked (423)
    case rateLimited                          // too many attempts (429)
    case noLinkedEmployee                     // user has no Mitarbeiter; link it in the web app
}

/// The documentation was changed elsewhere after the editor read it. Nothing was written.
public struct DocumentationConflict: Error, Equatable, Sendable {
    public var current: String
    public init(current: String) { self.current = current }
}

/// Result of the password step. Accounts with TOTP need a second step (`submitMFA`).
public enum SignInResult: Sendable {
    case signedIn(Session)
    case mfaRequired
}

// MARK: - The boundary

/// One method per thing a screen needs. **Read-only by design**, with one
/// exception: `saveDocumentation` writes a treatment's documentation text.
/// Nothing else is created, edited or deleted. Implementations: `MockTToolsAPI`
/// (fake seed data) and `LiveTToolsAPI` (the ttools.app backend).
public protocol TToolsAPI: Sendable {
    // Auth
    /// `practice` is the "Einrichtung"; the backend principal is "<practice>_<username>".
    func signIn(practice: String, username: String, password: String) async throws -> SignInResult
    func submitMFA(code: String) async throws -> Session
    func restoreSession() async throws -> Session?
    func signOut() async

    // Reference data, cached per session
    func employees() async throws -> [Employee]
    func rooms() async throws -> [Room]
    func treatmentTypes() async throws -> [TreatmentType]

    // Calendar
    func appointments(for employee: EmployeeID, in range: DateInterval) async throws -> [Appointment]
    func blockedIntervals(for employee: EmployeeID, in range: DateInterval) async throws -> [BlockedInterval]

    // Detail incl. documentation
    func appointmentDetail(_ id: AppointmentID) async throws -> AppointmentDetail
    /// The only write: replaces the documentation text of one treatment. Returns the fresh detail.
    /// Throws `DocumentationConflict` when the stored text is no longer `previous`.
    func saveDocumentation(_ text: String, for id: AppointmentID, replacing previous: String) async throws -> AppointmentDetail
}
