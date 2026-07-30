import Foundation

/// Pure date/time helpers (FUNCTIONALITY.md §5). Dates and times-of-day are both
/// modeled as `Date`; event start/end times are anchored to their day's date.
public enum DateTimeUtilities {

    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    // MARK: - Date construction

    /// Local start-of-day for a date.
    public static func startOfDay(_ date: Date) -> Date { gregorian.startOfDay(for: date) }

    /// Today at the given time-of-day — a default seed for time pickers.
    public static func time(hour: Int, minute: Int) -> Date {
        gregorian.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    /// End-of-day (`23:59:59`) for a day — the "due by end of day" default used
    /// for date-only deadlines (see ``Task/hasDeadlineTime``).
    public static func endOfDay(_ day: Date) -> Date {
        dateBySetting(day: day, hour: 23, minute: 59, second: 59)
    }

    /// Combines a day's calendar date with a time-of-day into a single `Date`.
    public static func combine(day: Date, time: Date) -> Date {
        let t = gregorian.dateComponents([.hour, .minute], from: time)
        return dateBySetting(day: day, hour: t.hour ?? 0, minute: t.minute ?? 0, second: 0)
    }

    // MARK: - Display

    /// Localized short date (like JS `toLocaleDateString`).
    public static func shortDate(_ date: Date, locale: Locale = .current) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.dateStyle = .short
        df.timeStyle = .none
        return df.string(from: date)
    }

    /// Localized deadline display. Appends `"at <time>"` when `hasTime` is set.
    public static func formatDeadline(_ deadline: Date, hasTime: Bool, locale: Locale = .current) -> String {
        let dateDisplay = shortDate(deadline, locale: locale)
        guard hasTime else { return dateDisplay }
        let tf = DateFormatter()
        tf.locale = locale
        tf.dateStyle = .none
        tf.timeStyle = .short
        return "\(dateDisplay) at \(tf.string(from: deadline))"
    }

    // MARK: - Helpers

    private static func dateBySetting(day: Date, hour: Int, minute: Int, second: Int) -> Date {
        let d = gregorian.dateComponents([.year, .month, .day], from: day)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        c.hour = hour; c.minute = minute; c.second = second
        return gregorian.date(from: c) ?? day
    }
}
