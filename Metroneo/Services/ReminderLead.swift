import Foundation

/// The early-reminder lead options a reminder's alarm can take (R4.2): a fixed
/// preset set plus a custom duration. Every value is expressed in **minutes
/// before** the due date (`0` = "at time"), mapped to an `EKAlarm.relativeOffset`.
public enum ReminderLead: Equatable, Hashable, Sendable {
    case preset(minutes: Int)
    case custom(minutes: Int)

    /// The preset ladder shown in the editor's early-reminder picker (R4.2).
    public static let presets: [Int] = [0, 5, 15, 30, 60, 120, 1440, 2880]

    public var minutes: Int {
        switch self {
        case .preset(let m), .custom(let m): return m
        }
    }

    /// A custom lead must be > 0; "at time" is the `0` preset.
    public var isValid: Bool {
        switch self {
        case .preset(let m): return Self.presets.contains(m)
        case .custom(let m): return m > 0
        }
    }

    /// Whether a lead of `minutes` is one of the presets (else it's a custom lead).
    public static func isPreset(_ minutes: Int) -> Bool { presets.contains(minutes) }

    /// A human label for a lead of `minutes` before the due date (R4.2) — used for
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
