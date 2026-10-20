import DesignSystem
import Domain
import Foundation

/// Settings for the "next appointment" watch feature. Contains no patient data.
public struct WatchSettings: Codable, Equatable, Sendable {
    public enum NameDisplay: String, Codable, CaseIterable, Sendable, Identifiable {
        case full, initials, hidden
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .full: "Vollständig"
            case .initials: "Initialen"
            case .hidden: "Ausblenden"
            }
        }
    }

    public static let leadTimeOptions = [0, 2, 5, 10, 15, 30]

    public var isEnabled = false
    public var leadMinutes = 10
    public var nameDisplay: NameDisplay = .initials
    public var showTreatment = true
    public var showRoom = true
    public var haptic = true

    public init(isEnabled: Bool = false, leadMinutes: Int = 10, nameDisplay: NameDisplay = .initials,
                showTreatment: Bool = true, showRoom: Bool = true, haptic: Bool = true) {
        self.isEnabled = isEnabled
        self.leadMinutes = leadMinutes
        self.nameDisplay = nameDisplay
        self.showTreatment = showTreatment
        self.showRoom = showRoom
        self.haptic = haptic
    }

    public static func leadTimeTitle(_ minutes: Int) -> String {
        minutes == 0 ? "Zum Beginn" : "\(minutes) Min. vorher"
    }
}

/// One appointment as the watch sees it: already formatted on the phone, so the
/// watch never gets more than the privacy setting allows.
public struct UpcomingItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Style: String, Codable, Sendable { case kg, mld, mldLong, device, heat, cold, other, blocker }

    public let id: String
    public var start: Date
    public var end: Date
    public var title: String
    public var subtitle: String?
    public var room: String?
    public var style: Style
    public var isCancelled: Bool
    /// "6/6". No name in it, so it is sent whatever the privacy setting.
    public var session: String?
    /// n == m: the prescription is used up after this appointment.
    public var isLastSession: Bool
    /// Reception checked the patient in, as of the last sync. Contains no name.
    public var isCheckedIn: Bool

    public init(id: String, start: Date, end: Date, title: String, subtitle: String? = nil, room: String? = nil,
                style: Style, isCancelled: Bool = false, session: String? = nil, isLastSession: Bool = false,
                isCheckedIn: Bool = false) {
        self.id = id; self.start = start; self.end = end; self.title = title
        self.subtitle = subtitle; self.room = room; self.style = style; self.isCancelled = isCancelled
        self.session = session; self.isLastSession = isLastSession; self.isCheckedIn = isCheckedIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, title, subtitle, room, style, isCancelled, session, isLastSession, isCheckedIn
    }

    /// Lenient for the fields added later, so a payload from an older phone app still decodes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        style = try c.decode(Style.self, forKey: .style)
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        session = try c.decodeIfPresent(String.self, forKey: .session)
        isLastSession = try c.decodeIfPresent(Bool.self, forKey: .isLastSession) ?? false
        isCheckedIn = try c.decodeIfPresent(Bool.self, forKey: .isCheckedIn) ?? false
    }

    public var treatmentStyle: TreatmentStyle { TreatmentStyle(rawValue: style.rawValue) ?? .other }
}

/// What the phone sends via `updateApplicationContext`. Only the latest one matters.
public struct UpcomingPayload: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var settings: WatchSettings
    public var items: [UpcomingItem]

    public init(generatedAt: Date, settings: WatchSettings, items: [UpcomingItem]) {
        self.generatedAt = generatedAt
        self.settings = settings
        self.items = items
    }

    public static func disabled(at date: Date) -> UpcomingPayload {
        UpcomingPayload(generatedAt: date, settings: WatchSettings(isEnabled: false), items: [])
    }

    public static let maxItems = 40
    public static let staleAfter: TimeInterval = 2 * 3600

    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(generatedAt) > Self.staleAfter }

    /// The appointment to show at `date`: the first one that has not ended and is not cancelled.
    public func next(at date: Date) -> UpcomingItem? {
        items.first { $0.end > date && !$0.isCancelled }
    }

    /// Remaining appointments today after `next`.
    public func remainingToday(after date: Date) -> [UpcomingItem] {
        let cal = PracticeCalendar.calendar
        let nextID = next(at: date)?.id
        return items.filter { $0.end > date && $0.id != nextID && cal.isDate($0.start, inSameDayAs: date) }
    }

    /// Treatments still ahead today, including the running one. Blockers and cancelled ones don't count.
    public func treatmentsLeftToday(at date: Date) -> Int {
        let cal = PracticeCalendar.calendar
        return items.filter { $0.end > date && !$0.isCancelled && $0.style != .blocker && cal.isDate($0.start, inSameDayAs: date) }.count
    }
}

extension UpcomingPayload {
    public static func encode(_ payload: UpcomingPayload) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return try e.encode(payload)
    }

    public static func decode(_ data: Data) throws -> UpcomingPayload {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(UpcomingPayload.self, from: data)
    }
}
