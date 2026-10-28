import DesignSystem
import Domain
import Foundation
import Observation

public enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case agenda, day, week, month
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .agenda: "Liste"
        case .day: "Tag"
        case .week: "Woche"
        case .month: "Monat"
        }
    }
}

public enum LoadState: Equatable, Sendable {
    case idle, loading, loaded, failed(APIError)
}

/// State and loading for the calendar screens (agenda, day, week, month).
@MainActor @Observable
public final class CalendarModel {
    public var mode: CalendarMode = .week { didSet { if mode != oldValue { updateVisibleHours(); reloadIfNeeded() } } }
    public private(set) var anchor: Date {
        didSet {
            navigationDirection = anchor >= oldValue ? 1 : -1
            updateVisibleHours()
        }
    }
    public var showWeekend = false { didSet { if showWeekend != oldValue { updateVisibleHours(); reload() } } }
    public var minuteHeight: CGFloat = DS.Layout.minuteHeightDefault
    /// Compact width (iPhone): the week view shows this many consecutive days instead of the whole week.
    public var weekDayLimit: Int? { didSet { if weekDayLimit != oldValue { updateVisibleHours(); reloadIfNeeded() } } }
    public var employeeID: EmployeeID { didSet { if employeeID != oldValue { reload() } } }

    public private(set) var appointments: [Appointment] = [] { didSet { indexAppointments(); updateVisibleHours() } }
    /// `appointments` split by practice-calendar day, so the grid and month do not filter the full list per cell.
    private var appointmentsByDay: [Date: [Appointment]] = [:]
    /// +1 when the last navigation went forward in time, -1 backward. Drives the page transition.
    public private(set) var navigationDirection = 1
    public private(set) var blocked: [BlockedInterval] = []
    public private(set) var state: LoadState = .idle
    /// The range `appointments` and `blocked` currently hold.
    private var loadedRange: DateInterval?
    public var reference: ReferenceData

    /// Called after every successful load (the app uses it to resync the watch).
    public var onLoaded: (@MainActor () -> Void)?

    let api: any TToolsAPI
    let now: () -> Date
    private var loadTask: Task<Void, Never>?

    /// The grid's hour window: the practice default, widened so early or late
    /// appointments of the visible days are never clipped.
    public private(set) var dayStartHour = Int(DS.Layout.dayStartHour)
    public private(set) var dayEndHour = Int(DS.Layout.dayEndHour)

    private func updateVisibleHours() {
        let newDays = computeDays()
        if newDays != days { days = newDays }
        var lo = Int(DS.Layout.dayStartHour), hi = Int(DS.Layout.dayEndHour)
        if mode == .day || mode == .week {
            let cal = PracticeCalendar.self
            let first = days.first, last = days.last.map { cal.calendar.date(byAdding: .day, value: 1, to: $0)! }
            for a in appointments where a.start >= (first ?? .distantFuture) && a.start < (last ?? .distantPast) {
                lo = min(lo, cal.minuteOfDay(a.start) / 60)
                // An end on the next day (or at midnight) means the window runs to 24.
                hi = cal.calendar.isDate(a.end, inSameDayAs: a.start) ? max(hi, (cal.minuteOfDay(a.end) + 59) / 60) : 24
            }
        }
        if lo != dayStartHour { dayStartHour = lo }
        if hi != dayEndHour { dayEndHour = hi }
    }

    public init(api: any TToolsAPI, employeeID: EmployeeID, reference: ReferenceData, now: @escaping () -> Date = { .now }) {
        self.api = api
        self.employeeID = employeeID
        self.reference = reference
        self.now = now
        self.anchor = PracticeCalendar.startOfDay(now())
        updateVisibleHours()
    }

    private func indexAppointments() {
        appointmentsByDay = Dictionary(grouping: appointments) { PracticeCalendar.startOfDay($0.start) }
    }

    // MARK: Period

    /// Days shown as columns (week/day) or the month's visible weekdays. Cached: rebuilt when
    /// the anchor, mode, weekend toggle or day limit changes.
    public private(set) var days: [Date] = []

    private func computeDays() -> [Date] {
        let cal = PracticeCalendar.self
        switch mode {
        case .agenda, .day:
            return [anchor]
        case .week:
            if let limit = weekDayLimit { return windowDays(count: limit) }
            return cal.days(from: cal.startOfWeek(anchor), count: showWeekend ? 7 : 5)
        case .month:
            let month = cal.calendar.dateInterval(of: .month, for: anchor)!
            let first = cal.startOfWeek(month.start)
            let lastDay = cal.calendar.date(byAdding: .day, value: -1, to: month.end)!
            let last = cal.calendar.date(byAdding: .day, value: 7, to: cal.startOfWeek(lastDay))!
            let count = cal.calendar.dateComponents([.day], from: first, to: last).day!
            return cal.days(from: first, count: count).filter { showWeekend || !cal.isWeekend($0) }
        }
    }

    /// `count` consecutive visible days starting at the anchor (or the next visible day).
    func windowDays(count: Int) -> [Date] {
        var result: [Date] = []
        var day = anchor
        while result.count < count {
            if showWeekend || !PracticeCalendar.isWeekend(day) { result.append(day) }
            day = PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    /// Moves `anchor` by `count` visible days (weekends skipped unless shown).
    private func shiftVisible(_ count: Int, direction: Int) {
        var day = anchor
        var left = count
        while left > 0 {
            day = PracticeCalendar.calendar.date(byAdding: .day, value: direction, to: day)!
            if showWeekend || !PracticeCalendar.isWeekend(day) { left -= 1 }
        }
        anchor = day
    }

    /// Agenda and day load the whole strip week, so the strip's dots are right and
    /// switching days within the week needs no request.
    public var range: DateInterval {
        let days = mode == .agenda || mode == .day ? stripDays : self.days
        let end = PracticeCalendar.calendar.date(byAdding: .day, value: 1, to: days.last!)!
        return DateInterval(start: days.first!, end: end)
    }

    /// "12.–16. Okt. 2026", "Montag, 19. Oktober 2026", "Oktober 2026"
    public var title: String {
        let cal = PracticeCalendar.self
        switch mode {
        case .agenda, .day:
            return cal.format(anchor, "EEEdMMMyyyy")
        case .month:
            return cal.format(anchor, "MMMMyyyy")
        case .week:
            let d = days
            let first = d.first!, last = d.last!
            let sameMonth = cal.calendar.isDate(first, equalTo: last, toGranularity: .month)
            return sameMonth
                ? "\(cal.calendar.component(.day, from: first)).–\(cal.format(last, "dMMMyyyy"))"
                : "\(cal.format(first, "dMMM")) – \(cal.format(last, "dMMMyyyy"))"
        }
    }

    /// The week strip above the agenda and day views. Includes the weekend when it is shown,
    /// or when the selected day falls on one.
    public var stripDays: [Date] {
        let cal = PracticeCalendar.self
        let includeWeekend = showWeekend || cal.isWeekend(anchor)
        return cal.days(from: cal.startOfWeek(anchor), count: includeWeekend ? 7 : 5)
    }

    /// Big header title: "Heute", "Morgen", "Donnerstag", or the week/month title.
    public var headerTitle: String {
        switch mode {
        case .agenda, .day:
            PracticeCalendar.relativeDayName(anchor, now: now()) ?? PracticeCalendar.format(anchor, "EEEE")
        case .week, .month: title
        }
    }

    /// Line under the title: "Mittwoch, 14. Oktober · KW 42", or "15. Oktober 2026 · KW 42"
    /// when the title is a plain weekday.
    public var headerSubtitle: String? {
        let week = "KW \(PracticeCalendar.calendar.component(.weekOfYear, from: anchor))"
        switch mode {
        case .agenda, .day:
            let date = PracticeCalendar.relativeDayName(anchor, now: now()) == nil
                ? PracticeCalendar.format(anchor, "dMMMMyyyy") : PracticeCalendar.format(anchor, "EEEEdMMMM")
            return "\(date) · \(week)"
        case .week: return week
        case .month: return nil
        }
    }

    public var isShowingToday: Bool {
        switch mode {
        case .agenda, .day: isToday(anchor)
        case .week, .month: days.contains(where: isToday)
        }
    }

    public var accessibilityTitle: String {
        if mode == .day || mode == .agenda { return PracticeCalendar.format(anchor, "EEEEdMMMMyyyy") }
        guard mode == .week, let first = days.first, let last = days.last else { return title }
        return "\(PracticeCalendar.format(first, "dMMMM")) bis \(PracticeCalendar.format(last, "dMMMMyyyy"))"
    }

    public func isToday(_ day: Date) -> Bool { PracticeCalendar.calendar.isDate(day, inSameDayAs: now()) }
    public var currentDate: Date { now() }

    // MARK: Navigation

    public func step(_ direction: Int) {
        let cal = PracticeCalendar.calendar
        switch mode {
        case .agenda, .day:
            var next = cal.date(byAdding: .day, value: direction, to: anchor)!
            while !showWeekend && PracticeCalendar.isWeekend(next) { next = cal.date(byAdding: .day, value: direction, to: next)! }
            anchor = next
        case .week:
            if let limit = weekDayLimit { shiftVisible(limit, direction: direction) }
            else { anchor = cal.date(byAdding: .weekOfYear, value: direction, to: anchor)! }
        case .month: anchor = cal.date(byAdding: .month, value: direction, to: anchor)!
        }
        reloadIfNeeded()
    }

    /// Strip swipe: same weekday one week earlier or later.
    public func stepWeek(_ direction: Int) {
        var next = PracticeCalendar.calendar.date(byAdding: .weekOfYear, value: direction, to: anchor)!
        if !showWeekend {
            while PracticeCalendar.isWeekend(next) { next = PracticeCalendar.calendar.date(byAdding: .day, value: -1, to: next)! }
        }
        anchor = next
        reloadIfNeeded()
    }

    public func goToToday() { go(to: now()) }

    public func go(to date: Date, mode newMode: CalendarMode? = nil) {
        anchor = PracticeCalendar.startOfDay(date)
        if let newMode, newMode != mode { mode = newMode } else { reloadIfNeeded() }
    }

    // MARK: Loading

    /// Navigation inside the already loaded range (a day in the same week) needs no request.
    func reloadIfNeeded() {
        if state == .loaded, let loadedRange, loadedRange.start <= range.start, loadedRange.end >= range.end { return }
        reload()
    }

    public func reload() {
        loadTask?.cancel()
        let range = self.range, employee = employeeID
        state = .loading
        loadTask = Task { [api] in
            do {
                async let a = api.appointments(for: employee, in: range)
                async let b = api.blockedIntervals(for: employee, in: range)
                let (appointments, blocked) = try await (a, b)
                guard !Task.isCancelled else { return }
                self.appointments = appointments
                self.blocked = blocked
                self.loadedRange = range
                self.state = .loaded
                self.onLoaded?()
            } catch is CancellationError {
            } catch let error as APIError {
                guard !Task.isCancelled else { return }
                self.state = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(.server(status: 0))
            }
        }
    }

    /// Pull to refresh: waits for the load to finish.
    public func refresh() async {
        reload()
        await loadTask?.value
    }

    public func appointments(on day: Date) -> [Appointment] {
        appointmentsByDay[PracticeCalendar.startOfDay(day)] ?? []
    }

    /// Minutes the practice is open for this employee on `day` (default window minus blocked time),
    /// the denominator for the month's load. Falls back to 8 h when nothing is bookable.
    public func openMinutes(on day: Date) -> Int {
        let open = DayLayout.openMinutes(blocked: blocked, on: day, startHour: Int(DS.Layout.dayStartHour), endHour: Int(DS.Layout.dayEndHour))
        return open > 0 ? open : 8 * 60
    }

    /// Strip dot: at least one treatment that is not cancelled.
    public func hasAppointments(on day: Date) -> Bool {
        appointments(on: day).contains { $0.kind == .treatment && $0.status != .cancelled }
    }

    // MARK: Agenda

    public func agendaEntries(on day: Date) -> [AgendaEntry] {
        AgendaBuilder.entries(appointments, blocked: blocked, on: day)
    }

    public var nextUp: Appointment? { AgendaBuilder.nextUp(appointments, now: now()) }

    public func treatmentName(_ a: Appointment) -> String {
        if a.kind == .blocker { return a.note ?? "Freitext" }
        let services = a.services.compactMap { reference.treatmentType($0.treatmentTypeID) }
        guard let first = services.first else { return "Behandlung" }
        return services.count > 1 ? "\(first.name) +\(services.count - 1)" : first.name
    }

    public func roomName(_ a: Appointment) -> String? {
        reference.room(a.services.first(where: { $0.roomID != nil })?.roomID)?.name
    }

    public func style(_ a: Appointment) -> TreatmentStyle {
        a.kind == .blocker ? .blocker
            : TreatmentStyle(a.services.first.flatMap { reference.treatmentType($0.treatmentTypeID) }?.category ?? .other)
    }

    // MARK: Cards

    private func checkInState(_ a: Appointment) -> DSCheckInBadge.State? {
        switch a.checkIn(now: now()) {
        case .waiting: .waiting
        case .overdue: .overdue
        case .arrived, .none: nil
        }
    }

    public func card(for a: Appointment) -> EventCardModel {
        let primary = a.services.first.flatMap { reference.treatmentType($0.treatmentTypeID) }
        let title = a.kind == .blocker ? "Blockiert" : (a.patient?.listName ?? "Ohne Patient")
        return EventCardModel(
            id: a.id.raw, time: PracticeCalendar.time(a.start), title: title, session: a.sessionLabel,
            treatment: treatmentName(a), note: a.kind == .blocker ? nil : a.note, shortCode: primary?.shortCode,
            style: style(a), status: EventStatus(a.status), isSeries: a.seriesID != nil,
            room: a.kind == .blocker ? nil : roomName(a), isLastSession: a.isLastSession,
            isPast: (mode == .day || mode == .week) && a.end <= now(),
            checkIn: checkInState(a))
    }
}

extension TreatmentStyle {
    public init(_ category: TreatmentCategory) {
        switch category {
        case .kg: self = .kg
        case .mld: self = .mld
        case .mldLong: self = .mldLong
        case .device: self = .device
        case .heat: self = .heat
        case .cold: self = .cold
        case .other: self = .other
        }
    }
}

extension EventStatus {
    public init(_ status: Appointment.Status) {
        switch status {
        case .planned: self = .planned
        case .arrived: self = .arrived
        case .cancelled: self = .cancelled
        }
    }
}
