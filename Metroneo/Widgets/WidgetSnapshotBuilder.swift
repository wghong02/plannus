import Foundation

/// Builds a ``WidgetSnapshot`` from the app's read model (DESIGN — Widgets). Pure and
/// injectable-`now`, so it's directly unit-testable. Uses `PerformanceAnalytics` for
/// the trailing-week performance and pre-formats every string the widgets show.
/// App-target only — the widget extension consumes the finished snapshot.
public enum WidgetSnapshotBuilder {
    /// Cap on rows carried into a widget (a medium widget shows far fewer).
    public static let rowLimit = 8

    public static func make(
        items: [TaskItem],
        needsRating: [TaskItem],
        rated: [TaskItem],
        weights: PriorityWeights = .defaults,
        now: Date = Date()
    ) -> WidgetSnapshot {
        let tasks = items.prefix(rowLimit).map { item in
            WidgetTask(id: item.id, title: item.title,
                       subtitle: item.dueDate.map { DateTimeUtilities.formatDeadline($0, hasTime: item.hasDueTime) })
        }
        let unrated = needsRating.prefix(rowLimit).map { item in
            WidgetTask(id: item.id, title: item.title,
                       subtitle: item.completionDate.map { "Completed \(DateTimeUtilities.shortDate($0))" })
        }

        // Trailing week (7 daily buckets), weighted average, and recent rated.
        let samples = PerformanceAnalytics.samples(from: rated, weights: weights)
        let weekly = PerformanceAnalytics.trendSeries(samples, period: .week, now: now).map {
            WidgetDayBucket(label: $0.period, count: $0.taskCount, average: $0.average)
        }
        let windowed = PerformanceAnalytics.filteredTasks(samples, period: .week, now: now)
        let recent = PerformanceAnalytics.windowedRated(rated, period: .week, now: now, limit: 6).map {
            WidgetRated(id: $0.id, title: $0.title, rating: $0.rating ?? 0)
        }

        return WidgetSnapshot(
            tasks: Array(tasks),
            needsRating: Array(unrated),
            weekly: weekly,
            weeklyRatedTotal: windowed.count,
            weeklyAverage: PerformanceAnalytics.average(windowed),
            recentRated: recent,
            generatedAt: now
        )
    }
}
