import Foundation

/// Short German countdown texts, shared by the phone's next-up card and the watch.
public enum Countdown {
    /// "in 12 Min.", "in 1 Std. 5 Min.", "seit 8 Min."
    public static func text(start: Date, now: Date) -> String {
        if start > now {
            let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
            return minutes >= 60 ? "in \(minutes / 60) Std. \(minutes % 60) Min." : "in \(minutes) Min."
        }
        return "seit \(Int(now.timeIntervalSince(start) / 60)) Min."
    }

    /// "noch 8 Min." while an appointment runs.
    public static func remaining(end: Date, now: Date) -> String {
        "noch \(max(Int((end.timeIntervalSince(now) / 60).rounded(.up)), 0)) Min."
    }

    /// "20 Min.", "1 Std.", "1 Std. 15 Min."
    public static func duration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) Min." }
        return minutes % 60 == 0 ? "\(minutes / 60) Std." : "\(minutes / 60) Std. \(minutes % 60) Min."
    }
}

extension Appointment {
    public var durationMinutes: Int { Int(end.timeIntervalSince(start) / 60) }
    /// n == m: the prescription is used up after this one.
    public var isLastSession: Bool { sessionNumber != nil && sessionNumber == sessionsTotal }
    /// n == 1 of a multi-session prescription: a new patient or a new prescription.
    public var isFirstSession: Bool { sessionNumber == 1 && (sessionsTotal ?? 0) > 1 }
    public var sessionLabel: String? { sessionNumber.flatMap { n in sessionsTotal.map { "\(n)/\($0)" } } }
}

extension PracticeCalendar {
    /// "Heute", "Morgen", "Gestern", else nil.
    public static func relativeDayName(_ day: Date, now: Date) -> String? {
        let diff = calendar.dateComponents([.day], from: startOfDay(now), to: startOfDay(day)).day ?? 99
        switch diff {
        case 0: return "Heute"
        case 1: return "Morgen"
        case -1: return "Gestern"
        default: return nil
        }
    }
}

/// What the check-in flag means for her right now. Reception sets it; the app only shows it.
public enum CheckIn: Hashable, Sendable {
    /// Arrived, starts soon or is running: go and get the patient.
    case waiting
    /// Arrived, outside that window (earlier today, or far ahead).
    case arrived
    /// Start passed by a few minutes and not checked in.
    case overdue
    case none

    /// "Waiting" begins this long before the start.
    public static let waitingLead: TimeInterval = 15 * 60
    /// Not checked in this long after the start counts as overdue.
    public static let overdueAfter: TimeInterval = 5 * 60
}

extension Appointment {
    public func checkIn(now: Date) -> CheckIn {
        guard kind == .treatment else { return .none }
        switch status {
        case .cancelled: return .none
        case .arrived:
            return start.addingTimeInterval(-CheckIn.waitingLead) <= now && now < end ? .waiting : .arrived
        case .planned:
            return start.addingTimeInterval(CheckIn.overdueAfter) <= now && now < end ? .overdue : .none
        }
    }
}
