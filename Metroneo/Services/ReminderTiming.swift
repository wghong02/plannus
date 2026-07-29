import Foundation

/// The lead-time options a reminder can take (D9.1): a fixed preset set plus a
/// custom duration. Every value is expressed in **minutes before** the time key
/// (`0` = "at time").
public enum ReminderLead: Equatable, Hashable, Sendable {
    case preset(minutes: Int)
    case custom(minutes: Int)

    /// The preset ladder shown in the picker (D9.1 / REM-02).
    public static let presets: [Int] = [0, 5, 15, 30, 60, 120, 1440, 2880]

    public var minutes: Int {
        switch self {
        case .preset(let m), .custom(let m): return m
        }
    }

    /// A custom lead must be > 0; "at time" is the `0` preset (REM-02).
    public var isValid: Bool {
        switch self {
        case .preset(let m): return Self.presets.contains(m)
        case .custom(let m): return m > 0
        }
    }
}

/// Pure reminder scheduling math (D9.2 / REM-03, REM-04). The UI/notification
/// side effects live in the notification scheduler (Phase 6); this stays testable.
public enum ReminderTiming {

    /// The instant a reminder fires: `timeKey − leadMinutes` (D9.2). `nil` when the
    /// entry has no reminder or no time key (undated).
    public static func fireDate(for entry: Entry) -> Date? {
        guard let lead = entry.reminderLeadMinutes, let key = entry.timeKey else { return nil }
        return key.addingTimeInterval(TimeInterval(-lead * 60))
    }

    /// A reminder is scheduled only when its fire time is strictly in the future
    /// (a fire time already `≤ now` is skipped — D9.3 / REM-04).
    public static func shouldSchedule(fireDate: Date, now: Date = Date()) -> Bool {
        fireDate > now
    }
}
