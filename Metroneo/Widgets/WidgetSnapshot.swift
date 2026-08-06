import Foundation

/// The app↔widget data contract (DESIGN — Widgets). The app publishes a small,
/// self-contained snapshot to a shared **App Group** on every refresh; the widget
/// extension reads it in its timeline provider. Everything the widgets render is
/// pre-computed and pre-formatted here so the widget target needs only this one
/// file (no EventKit / analytics / SwiftData).
///
/// SHARED FILE: this must be a member of **both** the app target and the widget
/// extension target.

/// A reminder row for the Tasks / Needs-rating widgets.
public struct WidgetTask: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// Pre-formatted secondary line (due date/time, or "Completed <date>"), or nil.
    public let subtitle: String?
    public init(id: String, title: String, subtitle: String?) {
        self.id = id; self.title = title; self.subtitle = subtitle
    }
}

/// A rated reminder for the performance widgets.
public struct WidgetRated: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let rating: Int
    public init(id: String, title: String, rating: Int) {
        self.id = id; self.title = title; self.rating = rating
    }
}

/// One day of the trailing week for the performance chart.
public struct WidgetDayBucket: Codable, Hashable {
    public let label: String
    public let count: Int
    public let average: Double
    public init(label: String, count: Int, average: Double) {
        self.label = label; self.count = count; self.average = average
    }
}

/// The whole widget snapshot.
public struct WidgetSnapshot: Codable, Hashable {
    public var tasks: [WidgetTask]          // incomplete reminders (Tasks widget)
    public var needsRating: [WidgetTask]    // completed + unrated (Needs-rating widget)
    public var weekly: [WidgetDayBucket]    // last 7 days (performance widgets)
    public var weeklyRatedTotal: Int
    public var weeklyAverage: Double
    public var recentRated: [WidgetRated]   // recent rated reminders
    public var generatedAt: Date

    public init(tasks: [WidgetTask], needsRating: [WidgetTask], weekly: [WidgetDayBucket],
                weeklyRatedTotal: Int, weeklyAverage: Double, recentRated: [WidgetRated],
                generatedAt: Date) {
        self.tasks = tasks; self.needsRating = needsRating; self.weekly = weekly
        self.weeklyRatedTotal = weeklyRatedTotal; self.weeklyAverage = weeklyAverage
        self.recentRated = recentRated; self.generatedAt = generatedAt
    }

    public static let empty = WidgetSnapshot(
        tasks: [], needsRating: [], weekly: [], weeklyRatedTotal: 0, weeklyAverage: 0,
        recentRated: [], generatedAt: .distantPast
    )
}

/// Reads/writes the snapshot in the shared App Group. `defaults` is injectable for
/// tests (a throwaway suite instead of the real group).
public enum WidgetSnapshotStore {
    /// Must match the App Group capability added to both targets in Xcode.
    public static let appGroup = "group.com.gladiolus.Metroneo"
    public static let key = "widget.snapshot.v1"

    public static func sharedDefaults() -> UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func write(_ snapshot: WidgetSnapshot, to defaults: UserDefaults? = sharedDefaults()) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func read(from defaults: UserDefaults? = sharedDefaults()) -> WidgetSnapshot {
        guard let defaults, let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }
}

/// Lets `TaskService` hand a freshly-built snapshot to whoever persists it, without
/// depending on WidgetKit. The app injects a WidgetKit-backed implementation; tests
/// inject a spy.
public protocol WidgetSnapshotPublishing: AnyObject {
    func publish(_ snapshot: WidgetSnapshot)
}
