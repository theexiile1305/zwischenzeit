import Foundation

/// The one calendar all grid math and formatting uses: Gregorian, German,
/// Monday first, Europe/Berlin, regardless of the device's settings.
public enum PracticeCalendar {
    public static let timeZone = TimeZone(identifier: "Europe/Berlin")!
    public static let locale = Locale(identifier: "de_DE")

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()

    /// Start of the Monday-based week containing `date`.
    public static func startOfWeek(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    public static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// `days` consecutive day starts beginning at `start`, DST-safe.
    public static func days(from start: Date, count: Int) -> [Date] {
        (0..<count).map { calendar.date(byAdding: .day, value: $0, to: startOfDay(start))! }
    }

    /// Wall-clock time on `day` (e.g. 08:40 Berlin time), DST-safe.
    public static func date(on day: Date, hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Minutes since local midnight, using wall-clock time (a DST day still runs 0…1439).
    public static func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    public static func isWeekend(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date)
    }

    public static func format(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "09:40"
    public static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = locale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
