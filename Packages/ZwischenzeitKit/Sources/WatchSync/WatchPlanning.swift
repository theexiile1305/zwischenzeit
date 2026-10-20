import Domain
import Foundation

/// Phone side: turns appointments into the watch payload, applying the privacy settings.
public enum UpcomingBuilder {
    public static func build(_ appointments: [Appointment], reference: ReferenceData,
                             settings: WatchSettings, now: Date) -> UpcomingPayload {
        guard settings.isEnabled else { return .disabled(at: now) }
        let items = appointments
            .filter { $0.end > now }
            .sorted { ($0.start, $0.id.raw) < ($1.start, $1.id.raw) }
            .prefix(UpcomingPayload.maxItems)
            .map { item(for: $0, reference: reference, settings: settings) }
        return UpcomingPayload(generatedAt: now, settings: settings, items: Array(items))
    }

    static func item(for a: Appointment, reference: ReferenceData, settings: WatchSettings) -> UpcomingItem {
        let type = a.services.first.flatMap { reference.treatmentType($0.treatmentTypeID) }
        let treatment = type?.name
        let title: String
        if a.kind == .blocker {
            title = a.note ?? "Blockierte Zeit"
        } else if let p = a.patient {
            switch settings.nameDisplay {
            case .full: title = p.fullName
            case .initials: title = p.initials
            case .hidden: title = treatment ?? "Termin"
            }
        } else {
            title = "Termin"
        }
        let showSubtitle = settings.showTreatment && a.kind != .blocker && !(settings.nameDisplay == .hidden)
        let style: UpcomingItem.Style = a.kind == .blocker ? .blocker : UpcomingItem.Style(rawValue: (type?.category ?? .other).rawValue) ?? .other
        return UpcomingItem(
            id: a.id.raw, start: a.start, end: a.end, title: title,
            subtitle: showSubtitle ? treatment : nil,
            room: settings.showRoom ? reference.room(a.services.first?.roomID)?.name : nil,
            style: style, isCancelled: a.status == .cancelled,
            session: a.kind == .blocker ? nil : a.sessionLabel, isLastSession: a.isLastSession,
            isCheckedIn: a.status == .arrived)
    }
}

/// Watch side: when each heads-up notification fires.
public enum NotificationPlanner {
    public struct Planned: Equatable, Sendable {
        public let item: UpcomingItem
        public let fireDate: Date
    }

    public static let maxPending = 20

    /// One notification per non-cancelled appointment, at `start − lead`. If the
    /// previous appointment is still running then, fire when it ends instead.
    /// Times already past are skipped.
    public static func plan(_ payload: UpcomingPayload, now: Date) -> [Planned] {
        guard payload.settings.isEnabled else { return [] }
        let lead = TimeInterval(payload.settings.leadMinutes * 60)
        let items = payload.items.filter { !$0.isCancelled }.sorted { $0.start < $1.start }
        var out: [Planned] = []
        var previousEnd: Date?
        for item in items {
            var fire = item.start.addingTimeInterval(-lead)
            if let previousEnd, previousEnd > fire, previousEnd <= item.start { fire = previousEnd }
            previousEnd = max(previousEnd ?? item.end, item.end)
            guard fire > now else { continue }
            out.append(Planned(item: item, fireDate: fire))
            if out.count == maxPending { break }
        }
        return out
    }
}

/// Watch widget: when the complication should switch to the next appointment.
public enum WidgetTimelinePlanner {
    public struct Entry: Equatable, Sendable {
        public let date: Date
        public let next: UpcomingItem?
    }

    /// An entry now, then one at each appointment's end (the face flips to the following one).
    public static func entries(_ payload: UpcomingPayload, now: Date) -> [Entry] {
        guard payload.settings.isEnabled else { return [Entry(date: now, next: nil)] }
        var dates = [now]
        dates += payload.items.filter { !$0.isCancelled && $0.end > now }.map(\.end)
        return dates.sorted().map { Entry(date: $0, next: payload.next(at: $0)) }
    }
}
