import WidgetKit
import SwiftUI
import AppIntents
import EventKit

// Widget extension shared plumbing (DESIGN — Widgets). The extension target also
// includes `WidgetSnapshot.swift` (shared with the app); everything the widgets show
// comes from the snapshot the app publishes to the App Group.

// MARK: - Timeline

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The medium Performance widget's toggle state (chart vs. rated list).
    let showRated: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: .empty, showRated: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        // The app reloads timelines on every refresh (AppWidgetPublisher); this
        // periodic policy is only a fallback so the widget never goes fully stale.
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
    private func current() -> WidgetEntry {
        let showRated = WidgetSnapshotStore.sharedDefaults()?.bool(forKey: PerformanceWidgetMode.key) ?? false
        return WidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.read(), showRated: showRated)
    }
}

// MARK: - Intents

/// Completes a reminder from the Tasks widget's leading circle. Requires the widget
/// extension to carry `NSRemindersFullAccessUsageDescription`; EventKit authorization
/// is shared with the containing app.
struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Reminder"
    @Parameter(title: "Reminder") var reminderId: String

    init() {}
    init(reminderId: String) { self.reminderId = reminderId }

    func perform() async throws -> some IntentResult {
        let store = EKEventStore()
        if let reminder = store.calendarItems(withExternalIdentifier: reminderId)
            .compactMap({ $0 as? EKReminder }).first {
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
        // Optimistically drop it so the widget reflects the completion immediately;
        // the app republishes an authoritative snapshot on its next refresh.
        var snapshot = WidgetSnapshotStore.read()
        snapshot.tasks.removeAll { $0.id == reminderId }
        WidgetSnapshotStore.write(snapshot)
        return .result()
    }
}

enum PerformanceWidgetMode { static let key = "widget.performance.showRated" }

/// Flips the medium Performance widget between the weekly chart and the rated list.
struct TogglePerformanceModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Performance View"
    func perform() async throws -> some IntentResult {
        let defaults = WidgetSnapshotStore.sharedDefaults()
        let current = defaults?.bool(forKey: PerformanceWidgetMode.key) ?? false
        defaults?.set(!current, forKey: PerformanceWidgetMode.key)
        return .result()
    }
}

// MARK: - Reusable views

/// A reminder row; `completable` adds the leading complete circle (Tasks widget).
struct WidgetTaskRow: View {
    let task: WidgetTask
    var completable = false
    var body: some View {
        HStack(spacing: 8) {
            if completable {
                Button(intent: CompleteReminderIntent(reminderId: task.id)) {
                    Image(systemName: "circle").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title).font(.subheadline).lineLimit(1)
                if let subtitle = task.subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A compact 7-day bar chart of daily average performance (empty days dimmed).
struct WeeklyBars: View {
    let weekly: [WidgetDayBucket]
    var height: CGFloat = 46
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(weekly.enumerated()), id: \.offset) { _, bucket in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .opacity(bucket.count == 0 ? 0.18 : 1)
                    .frame(height: max(3, CGFloat(bucket.average) / 100 * height))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// The "rated reminders" list used by the Performance widgets.
struct RatedList: View {
    let items: [WidgetRated]
    var limit = 4
    var body: some View {
        if items.isEmpty {
            Text("Nothing rated this week").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.prefix(limit)) { item in
                    HStack {
                        Text(item.title).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.rating)").font(.caption.bold()).foregroundStyle(.tint)
                    }
                }
            }
        }
    }
}

/// A headline "This Week" summary: weighted average + rated count.
struct WeeklySummary: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(format: "%.0f", snapshot.weeklyAverage))
                .font(.title.bold()).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("avg").font(.caption2).foregroundStyle(.secondary)
                Text("\(snapshot.weeklyRatedTotal) rated").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
