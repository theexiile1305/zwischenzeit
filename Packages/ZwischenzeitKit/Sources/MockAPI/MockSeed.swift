import Domain
import Foundation

/// Deterministic fake practice: 3 employees, ~40 fictional patients, five weeks of
/// appointments around `now`, covering every card variant.
struct MockSeed: Sendable {
    let employees: [Employee]
    let rooms: [Room]
    let treatmentTypes: [TreatmentType]
    let patients: [Patient]
    let prescriptions: [Prescription]
    let appointments: [Appointment]
    let weekStart: Date

    init(now: Date) {
        let cal = PracticeCalendar.self
        employees = [
            Employee(id: EmployeeID("e1"), displayName: "Anna Hartmann", initials: "AH"),
            Employee(id: EmployeeID("e2"), displayName: "Jonas Keller", initials: "JK"),
            Employee(id: EmployeeID("e3"), displayName: "Mira Brandt", initials: "MB"),
        ]
        rooms = (1...4).map { Room(id: RoomID("r\($0)"), name: "Raum \($0)") }
        let types = [
            TreatmentType(id: TreatmentTypeID("kg"), name: "Krankengymnastik", category: .kg, defaultDurationMinutes: 20, maxGroupSize: 1),
            TreatmentType(id: TreatmentTypeID("mld30"), name: "Lymphdrainage 30 Min.", category: .mld, defaultDurationMinutes: 30, maxGroupSize: 1),
            TreatmentType(id: TreatmentTypeID("mld45"), name: "Lymphdrainage 45 Min.", category: .mldLong, defaultDurationMinutes: 45, maxGroupSize: 1),
            TreatmentType(id: TreatmentTypeID("kgg"), name: "Gerätetraining", category: .device, defaultDurationMinutes: 60, maxGroupSize: 3, shortCode: "KGG"),
            TreatmentType(id: TreatmentTypeID("heat"), name: "Wärmeanwendung", category: .heat, defaultDurationMinutes: 20, maxGroupSize: 1),
            TreatmentType(id: TreatmentTypeID("cold"), name: "Kälteanwendung", category: .cold, defaultDurationMinutes: 10, maxGroupSize: 1),
            TreatmentType(id: TreatmentTypeID("mt"), name: "Manuelle Therapie", category: .other, defaultDurationMinutes: 20, maxGroupSize: 1),
        ]
        treatmentTypes = types

        let first = ["Anna", "Ben", "Clara", "David", "Emil", "Frieda", "Greta", "Hannes", "Ida", "Jakob",
                     "Karla", "Luis", "Marta", "Nils", "Olga", "Paul", "Rosa", "Sven", "Tilda", "Udo"]
        let last = ["Achternbusch", "Bergmann", "Claasen", "Dornfeld", "Ehrlich", "Falkenrath", "Grünberg",
                    "Hollerbach", "Imhoff", "Jansen", "Kranich", "Lindqvist-Oberhauser", "Morgenstern", "Nolte",
                    "Ostwald", "Pfeiffer", "Quandt", "Rautenberg", "Seidel", "Tannhäuser"]
        var patients: [Patient] = []
        for i in 0..<40 {
            patients.append(Patient(id: PatientID("p\(i)"), firstName: first[(i * 7) % first.count], lastName: last[i % last.count]))
        }
        self.patients = patients
        var prescriptions: [Prescription] = []
        for (i, p) in patients.enumerated() {
            prescriptions.append(Prescription(id: PrescriptionID("rx\(i)"), patientID: p.id,
                                              number: "R-\(24_000 + i * 37)-\(i % 9)", sessionsTotal: i % 3 == 0 ? 10 : 6,
                                              status: .open))
            if i % 5 == 0 {
                prescriptions.append(Prescription(id: PrescriptionID("rx\(i)b"), patientID: p.id,
                                                  number: "R-\(19_000 + i * 11)-\(i % 7)", sessionsTotal: 6, status: .completed))
            }
        }
        self.prescriptions = prescriptions

        weekStart = cal.startOfWeek(now)
        var rng = SplitMix64(seed: 42)
        var result: [Appointment] = []
        var sessionCount: [PrescriptionID: Int] = [:]
        var counter = 0
        func nextID() -> AppointmentID { counter += 1; return AppointmentID("a\(counter)") }

        let days = cal.days(from: cal.calendar.date(byAdding: .day, value: -14, to: weekStart)!, count: 35)
        for day in days where !cal.isWeekend(day) {
            let weekday = cal.calendar.component(.weekday, from: day) // 2 = Monday
            for (ei, employee) in employees.enumerated() {
                // Group device training: Mon + Fri 11:00, three participants.
                if (weekday == 2 || weekday == 6) && ei == 0 {
                    let group = GroupID("g-\(Int(day.timeIntervalSince1970))")
                    for k in 0..<3 {
                        let p = patients[(k * 11 + weekday) % patients.count]
                        result.append(Self.make(id: nextID(), day: day, h: 11, m: 0, minutes: 60, type: types[3], employee: employee,
                                                patient: p, rx: prescriptions.first { $0.patientID == p.id }!, room: rooms[3],
                                                now: now, sessions: &sessionCount, group: group, rng: &rng))
                    }
                }
                // Team meeting blocker: Wednesday 10:00–11:00.
                if weekday == 4 {
                    result.append(Appointment(id: nextID(), kind: .blocker, status: .planned,
                                              start: cal.date(on: day, hour: 10, minute: 0), end: cal.date(on: day, hour: 11, minute: 0),
                                              services: [AppointmentService(id: "b\(counter)", treatmentTypeID: types[6].id, employeeID: employee.id, durationMinutes: 60)],
                                              note: "Teambesprechung"))
                }
                var minute = 8 * 60
                while minute < 18 * 60 {
                    let free = Self.isFree(minute: minute, weekday: weekday, employeeIndex: ei)
                    if !free { minute += 10; continue }
                    if rng.next() % 6 == 0 { minute += 10; continue } // gaps
                    let type = Self.pickType(types, &rng)
                    let duration = type.defaultDurationMinutes
                    guard (0..<duration).allSatisfy({ Self.isFree(minute: minute + $0, weekday: weekday, employeeIndex: ei) }),
                          minute + duration <= 18 * 60 else { minute += 10; continue }
                    let p = patients[Int(rng.next() % UInt64(patients.count))]
                    let rx = prescriptions.first { $0.patientID == p.id }!
                    let series = (Int(p.id.raw.dropFirst())! % 4 == 0) ? SeriesID("s-\(p.id.raw)-\(minute)") : nil
                    var a = Self.make(id: nextID(), day: day, h: minute / 60, m: minute % 60, minutes: duration, type: type,
                                      employee: employee, patient: p, rx: rx, room: rooms[Int(rng.next() % 3)],
                                      now: now, sessions: &sessionCount, group: nil, rng: &rng)
                    a.seriesID = series
                    result.append(a)
                    minute += duration
                }
            }
        }
        appointments = result
    }

    /// Off-duty and not-bookable times (the gray bands).
    func blocked(for employee: EmployeeID, in range: DateInterval) -> [BlockedInterval] {
        let cal = PracticeCalendar.self
        let ei = employees.firstIndex { $0.id == employee } ?? 0
        var out: [BlockedInterval] = []
        var day = cal.startOfDay(range.start)
        while day < range.end {
            let weekday = cal.calendar.component(.weekday, from: day)
            if cal.isWeekend(day) {
                out.append(BlockedInterval(start: day, end: cal.calendar.date(byAdding: .day, value: 1, to: day)!))
            } else {
                out.append(BlockedInterval(start: day, end: cal.date(on: day, hour: 8, minute: 0)))
                out.append(BlockedInterval(start: cal.date(on: day, hour: 12, minute: 0), end: cal.date(on: day, hour: 12, minute: 30)))
                if weekday == 3 && ei == 0 {
                    out.append(BlockedInterval(start: cal.date(on: day, hour: 8, minute: 0), end: cal.date(on: day, hour: 12, minute: 0)))
                }
                out.append(BlockedInterval(start: cal.date(on: day, hour: 18, minute: 0), end: cal.calendar.date(byAdding: .day, value: 1, to: day)!))
            }
            day = cal.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    private static func isFree(minute: Int, weekday: Int, employeeIndex: Int) -> Bool {
        if (12 * 60..<12 * 60 + 30).contains(minute) { return false }              // lunch
        if weekday == 3 && employeeIndex == 0 && minute < 12 * 60 { return false }  // Tuesday morning off
        if weekday == 4 && (10 * 60..<11 * 60).contains(minute) { return false }    // team meeting
        if (weekday == 2 || weekday == 6) && employeeIndex == 0 && (11 * 60..<12 * 60).contains(minute) { return false } // group
        return true
    }

    private static func pickType(_ types: [TreatmentType], _ rng: inout SplitMix64) -> TreatmentType {
        switch rng.next() % 20 {
        case 0..<9: types[0]
        case 9..<14: types[1]
        case 14..<15: types[2]
        case 15..<17: types[4]
        case 17..<18: types[5]
        default: types[6]
        }
    }

    private static func make(id: AppointmentID, day: Date, h: Int, m: Int, minutes: Int, type: TreatmentType,
                             employee: Employee, patient: Patient, rx: Prescription, room: Room, now: Date,
                             sessions: inout [PrescriptionID: Int], group: GroupID?, rng: inout SplitMix64) -> Appointment {
        let start = PracticeCalendar.date(on: day, hour: h, minute: m)
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        let n = (sessions[rx.id] ?? 0) % rx.sessionsTotal + 1
        sessions[rx.id] = n
        let roll = rng.next() % 25
        let status: Appointment.Status = roll == 0 ? .cancelled : (start < now.addingTimeInterval(10 * 60) && roll != 1 ? .arrived : .planned)
        return Appointment(
            id: id, kind: .treatment, status: status, start: start, end: end, patient: patient, prescriptionID: rx.id,
            sessionNumber: n, sessionsTotal: rx.sessionsTotal, groupID: group,
            services: [AppointmentService(id: "\(id.raw)-s0", treatmentTypeID: type.id, employeeID: employee.id,
                                          roomID: room.id, durationMinutes: minutes)],
            note: type.category == .mld && status == .arrived && end < now ? "Leistung erbracht" : nil)
    }
}

/// Small deterministic RNG so the seed is the same on every launch and in tests.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
