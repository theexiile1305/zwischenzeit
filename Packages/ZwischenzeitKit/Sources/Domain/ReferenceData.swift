import Foundation

/// Reference data loaded once per session, with lookups by ID.
public struct ReferenceData: Sendable, Equatable {
    public var employees: [Employee]
    public var rooms: [Room]
    public var treatmentTypes: [TreatmentType]

    public init(employees: [Employee] = [], rooms: [Room] = [], treatmentTypes: [TreatmentType] = []) {
        self.employees = employees
        self.rooms = rooms
        self.treatmentTypes = treatmentTypes
    }

    public static func load(from api: any TToolsAPI) async throws -> ReferenceData {
        async let e = api.employees()
        async let r = api.rooms()
        async let t = api.treatmentTypes()
        return try await ReferenceData(employees: e, rooms: r, treatmentTypes: t)
    }

    public func employee(_ id: EmployeeID) -> Employee? { employees.first { $0.id == id } }
    public func room(_ id: RoomID?) -> Room? { id.flatMap { id in rooms.first { $0.id == id } } }
    public func treatmentType(_ id: TreatmentTypeID) -> TreatmentType? { treatmentTypes.first { $0.id == id } }
}

extension Patient {
    /// "Bergmann, Anna", the list form the calendar uses.
    public var listName: String { "\(lastName), \(firstName)" }
    public var fullName: String { "\(firstName) \(lastName)" }
    public var initials: String { "\(firstName.prefix(1)). \(lastName.prefix(1))." }
}
