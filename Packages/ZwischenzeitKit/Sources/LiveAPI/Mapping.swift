import Domain
import Foundation

/// DTO → domain. Every rule that depends on how the backend encodes something lives here.
/// The rules mirror how the TTools web app draws the same data.
enum Mapping {
    static func employee(_ m: MitarbeiterDTO) -> Employee {
        let first = m.vorname?.trimmingCharacters(in: .whitespaces) ?? ""
        let last = m.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let display = [first.first.map { "\($0)." }, last.isEmpty ? nil : last].compactMap { $0 }.joined(separator: " ")
        let initials = m.kuerzel ?? String([first.first, last.first].compactMap { $0 }).uppercased()
        return Employee(id: EmployeeID(m.id.raw),
                        displayName: display.isEmpty ? "Mitarbeiter \(m.id.raw)" : display,
                        initials: initials.isEmpty ? "?" : initials)
    }

    /// nil for deleted rows and rows without a usable start time; skipped, not fatal.
    static func appointment(_ t: TerminDTO) -> Appointment? {
        // Like the web app: the day comes from `datum`, only the clock time from `uhrzeit`
        // (the date part of `uhrzeit` is not the appointment's day).
        guard t.trash != true, let day = t.datum.flatMap(dateTime).map(PracticeCalendar.startOfDay),
              let start = t.uhrzeit.flatMap({ clock($0, on: day) }) else { return nil }
        let leistungen = t.leistungen ?? []
        // Services run back to back from the start time.
        let services = leistungen.enumerated().map { i, l in
            AppointmentService(id: l.id?.raw ?? "\(t.id.raw)-\(i)",
                               treatmentTypeID: TreatmentTypeID(l.terminart?.id?.raw ?? "unbekannt"),
                               employeeID: EmployeeID(l.mitarbeiter?.id?.raw ?? ""),
                               roomID: l.raum?.id.map { RoomID($0.raw) },
                               durationMinutes: l.dauer?.value ?? 0)
        }
        let minutes = services.reduce(0) { $0 + $1.durationMinutes }
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))

        let patient: Patient? = t.kunde.flatMap { k in
            k.id.map { Patient(id: PatientID($0.raw), firstName: k.vorname ?? "", lastName: k.name ?? "") }
        }
        // "n/m": the prescription counter wins over the series counter, both 0-based on the wire.
        var counter: (Int, Int)?
        if let first = leistungen.first, let count = first.rezeptCount?.value, count > 0 {
            counter = ((first.rezeptIndex?.value ?? 0) + 1, count)
        } else if let count = t.terminSerieCount?.value, count > 0 {
            counter = ((t.terminSerieIndex?.value ?? 0) + 1, count)
        }
        let text = t.dokumentation?.text.flatMap { $0.isEmpty ? nil : $0 }

        return Appointment(
            id: AppointmentID(t.id.raw),
            kind: patient == nil ? .blocker : .treatment,   // no Kunde = "Freitext"
            status: status(t),
            start: start,
            end: end,
            patient: patient,
            prescriptionID: t.rezept?.id.map { PrescriptionID($0.raw) },
            sessionNumber: counter?.0,
            sessionsTotal: counter?.1,
            seriesID: t.dauerTermin?.id.map { SeriesID($0.raw) },
            groupID: t.gruppenTermin?.id.map { GroupID($0.raw) },
            services: services,
            note: patient == nil ? text : nil)
    }

    /// Cancelled by patient or practice, or a recorded no-show, all render as cancelled.
    static func status(_ t: TerminDTO) -> Appointment.Status {
        if t.abgesagtAm != nil || t.abgesagtDurchMandantAm != nil { return .cancelled }
        switch t.wahrgenommen {
        case true: return .arrived       // reception ticks it at check-in
        case false: return .cancelled
        case nil: return .planned
        }
    }

    static func treatmentType(_ a: TerminartDTO) -> TreatmentType {
        TreatmentType(id: TreatmentTypeID(a.id.raw), name: a.name ?? a.kurzName ?? "",
                      category: category(name: a.name, short: a.kurzName),
                      defaultDurationMinutes: a.takt?.value ?? 30, maxGroupSize: 1, shortCode: a.kurzName)
    }

    /// Colour family from the treatment name; the backend has no category field.
    static func category(name: String?, short: String?) -> TreatmentCategory {
        let s = [short, name].compactMap { $0 }.joined(separator: " ").lowercased()
        if s.contains("mld") || s.contains("lymph") { return s.contains("60") || s.contains("45") ? .mldLong : .mld }
        if s.contains("kgg") || s.contains("gerät") { return .device }
        if s.contains("wärme") || s.contains("fango") || s.contains("heißluft") || s.contains("heisse") { return .heat }
        if s.contains("kälte") || s.contains("kalt") || s.contains("kryo") { return .cold }
        if s.contains("kg") || s.contains("krankengymnastik") { return .kg }
        return .other
    }

    static func prescription(_ r: RezeptDTO, patient: PatientID) -> Prescription {
        let status: Prescription.Status = switch r.rezeptStatus?.value ?? 0 {
        case 0: .open
        case 1: .cancelled
        case 2, 3, 4: .completed
        default: .unknown
        }
        let total = (r.heilmittelLeistung ?? []).reduce(0) { $0 + ($1.anzahl?.value ?? 0) }
        return Prescription(id: PrescriptionID(r.id.raw), patientID: patient,
                            number: r.belegNummer ?? "", sessionsTotal: total, status: status)
    }

    // MARK: Blocked time

    static func blocked(_ u: UrlaubDTO) -> BlockedInterval? {
        guard let day = dateTime(u.datum).map(PracticeCalendar.startOfDay) else { return nil }
        if let von = u.von.flatMap({ clock($0, on: day) }), let bis = u.bis.flatMap({ clock($0, on: day) }), bis > von {
            return BlockedInterval(start: von, end: bis)
        }
        return BlockedInterval(start: day, end: nextDay(day))
    }

    /// Outside the employee's working windows is not bookable. Like the web app, a day on
    /// which the employee has no window at all is blocked entirely, but only if the practice
    /// keeps working times that day (otherwise nobody's calendar would show anything bookable).
    static func blocked(windows all: [MitarbeiterTerminDTO], employee: EmployeeID, day: Date) -> [BlockedInterval] {
        guard !all.isEmpty else { return [] }
        let dayEnd = nextDay(day)
        let mine = all.filter { $0.mitarbeiter?.id?.raw == employee.raw }
            .compactMap { w -> (Date, Date)? in
                guard let s = w.von.flatMap({ clock($0, on: day) }), let e = w.bis.flatMap({ clock($0, on: day) }), e > s else { return nil }
                return (s, e)
            }
            .sorted { $0.0 < $1.0 }
        var gaps: [BlockedInterval] = []
        var cursor = day
        for (s, e) in mine {
            if s > cursor { gaps.append(BlockedInterval(start: cursor, end: s)) }
            cursor = max(cursor, e)
        }
        if cursor < dayEnd { gaps.append(BlockedInterval(start: cursor, end: dayEnd)) }
        return gaps
    }

    // MARK: Formats (all wall-clock Europe/Berlin)

    static let dayFormatter = formatter("yyyy-MM-dd")
    private static let dateTimeFormatter = formatter("yyyy-MM-dd HH:mm")

    /// The clock time of a "yyyy-MM-dd HH:mm" value placed on `day`; the backend's date part
    /// of time fields is not reliable, so the web app ignores it too.
    static func clock(_ s: String, on day: Date) -> Date? {
        dateTime(s).map { t in
            let m = PracticeCalendar.minuteOfDay(t)
            return PracticeCalendar.date(on: day, hour: m / 60, minute: m % 60)
        }
    }

    static func dateTime(_ s: String) -> Date? {
        dateTimeFormatter.date(from: String(s.prefix(16))) ?? dayFormatter.date(from: String(s.prefix(10)))
    }

    private static func nextDay(_ day: Date) -> Date {
        PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: day)!
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = PracticeCalendar.calendar
        f.timeZone = PracticeCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
