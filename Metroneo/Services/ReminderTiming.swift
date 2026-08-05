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

    /// Whether a lead of `minutes` is one of the presets (else it's a custom lead).
    public static func isPreset(_ minutes: Int) -> Bool { presets.contains(minutes) }

    /// A human label for a lead of `minutes` before the time key (D9.1) — used for
    /// both presets and custom values (e.g. 0 → "At time", 90 → "1h 30m before",
    /// 2880 → "2 days before").
    public static func label(minutes: Int) -> String {
        guard minutes > 0 else { return "At time" }
        if minutes % 1440 == 0 { let d = minutes / 1440; return "\(d) day\(d == 1 ? "" : "s") before" }
        if minutes % 60 == 0 { let h = minutes / 60; return "\(h) hour\(h == 1 ? "" : "s") before" }
        if minutes < 60 { return "\(minutes) min before" }
        return "\(minutes / 60)h \(minutes % 60)m before"
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

    /// Count of **due/overdue** reminders as of `date` — entries with a reminder
    /// whose fire time has passed (`≤ date`) and that aren't completed. This is the
    /// app-icon badge number (D18); passing a notification's fire time gives the
    /// badge that notification should carry.
    public static func dueReminderCount(_ entries: [Entry], by date: Date = Date()) -> Int {
        entries.reduce(into: 0) { count, entry in
            guard !entry.isCompleted, let fire = fireDate(for: entry), fire <= date else { return }
            count += 1
        }
    }
}
