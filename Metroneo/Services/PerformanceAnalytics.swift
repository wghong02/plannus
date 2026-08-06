import Foundation

/// Time window for performance analytics (DESIGN D16).
public enum PerformancePeriod: String, CaseIterable {
    case week, month, threeMonths, year, allTime, custom

    public var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .threeMonths: return "3 Months"
        case .year: return "Year"
        case .allTime: return "All Time"
        case .custom: return "Custom"
        }
    }
}

/// Bucket size for the adaptive trend chart. The month-based tiers form an
/// escalation ladder (monthly → quarterly → half-year → yearly) so a long span
/// stays within 12 buckets.
public enum PerformanceGranularity: Equatable {
    case daily, weekly, biweekly, monthly, quarterly, halfYear, yearly

    public var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .halfYear: return "Half-Year"
        case .yearly: return "Yearly"
        }
    }

    /// Month step for month-based tiers; `nil` for day-based tiers.
    var monthStep: Int? {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .halfYear: return 6
        case .yearly: return 12
        case .daily, .weekly, .biweekly: return nil
        }
    }

    /// Day step for day-based tiers; `nil` for month-based tiers.
    var dayStep: Int? {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .biweekly: return 14
        case .monthly, .quarterly, .halfYear, .yearly: return nil
        }
    }
}

/// Trend of a data point relative to the previous one.
public enum PerformanceTrend: Equatable { case up, down, stable }

/// Summed estimated vs actual time (minutes) behind the time-tracking bars (D17),
/// over the entries in the selected period that recorded both durations.
public struct DurationTotals: Equatable {
    public var estimated: Int
    public var actual: Int
    /// Number of entries counted (0 ⇒ hide the section).
    public var count: Int
    public init(estimated: Int, actual: Int, count: Int) {
        self.estimated = estimated
        self.actual = actual
        self.count = count
    }
}

/// Number of tasks at a given performance level within a bucket.
public struct LevelCount: Equatable {
    public var level: PerformanceLevel
    public var count: Int
    public init(level: PerformanceLevel, count: Int) {
        self.level = level
        self.count = count
    }
}

/// One point in the trend series.
public struct PerformanceDataPoint: Equatable {
    public var period: String
    public var average: Double
    public var taskCount: Int
    /// Per-category breakdown of the bucket's tasks (for the distribution bars).
    public var levelCounts: [LevelCount]
    public var trend: PerformanceTrend

    public init(period: String, average: Double, taskCount: Int,
                levelCounts: [LevelCount] = [], trend: PerformanceTrend) {
        self.period = period
        self.average = average
        self.taskCount = taskCount
        self.levelCounts = levelCounts
        self.trend = trend
    }
}

/// A single rated data point for analytics — a date to place it on the timeline
/// and its 0–100 rating. The population is **rated reminders** (R2.3): a `TaskItem`
/// whose sidecar has a rating, placed by its completion date, else its due date.
public struct RatedSample: Equatable, Sendable {
    /// Placement date on the timeline (never nil for a mapped sample).
    public var completedAt: Date?
    public var performanceRating: Int
    /// Priority weight for the weighted average (DESIGN R7.3); `1` = unweighted.
    public var weight: Double

    public init(completedAt: Date?, performanceRating: Int, weight: Double = 1) {
        self.completedAt = completedAt
        self.performanceRating = performanceRating
        self.weight = weight
    }
}

/// Pure analytics over rated samples (DESIGN D16; population per R2.3).
public enum PerformanceAnalytics {

    /// Maps rated `TaskItem`s to samples (DESIGN R2.3), each carrying its priority
    /// weight (R7.3): only rated items count, placed by `placementDate`
    /// (completion, else due).
    public static func samples(from items: [TaskItem], weights: PriorityWeights = .defaults) -> [RatedSample] {
        items.compactMap { item in
            guard let rating = item.rating else { return nil }
            return RatedSample(completedAt: item.placementDate, performanceRating: rating,
                               weight: Double(weights.weight(for: item.priority)))
        }
    }


    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Start/end range for a period. `now` and `customStart` are injectable for tests.
    public static func dateRange(
        for period: PerformancePeriod,
        customStart: Date? = nil,
        now: Date = Date()
    ) -> (start: Date, end: Date) {
        let cal = calendar
        let end = now
        var start = now
        switch period {
        case .week:        start = cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:       start = cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths: start = cal.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:        start = cal.date(byAdding: .year, value: -1, to: now) ?? now
        case .allTime:     start = Date(timeIntervalSince1970: 0)
        case .custom:      start = customStart ?? (cal.date(byAdding: .day, value: -7, to: now) ?? now)
        }
        return (start, end)
    }

    /// Completed tasks whose `completedAt` falls within the analysis window. The
    /// window starts at the earliest trend bucket (not the raw period start) so the
    /// "Tasks Completed" stat and the chart always cover exactly the same tasks.
    public static func filteredTasks(
        _ tasks: [RatedSample],
        period: PerformancePeriod,
        customStart: Date? = nil,
        now: Date = Date()
    ) -> [RatedSample] {
        let start = alignedStart(for: period, tasks: tasks, customStart: customStart, now: now, cal: calendar)
        return tasks.filter { task in
            guard let d = task.completedAt else { return false }
            return d >= start && d <= now
        }
    }

    /// `durationTotals` over `TaskItem`s (DESIGN R2/D17): estimated + actual from
    /// the sidecar, placed by `placementDate`, scoped to the period.
    public static func durationTotals(
        _ items: [TaskItem],
        period: PerformancePeriod,
        customStart: Date? = nil,
        now: Date = Date()
    ) -> DurationTotals {
        let (start, end) = dateRange(for: period, customStart: customStart, now: now)
        let qualifying = items.filter { i in
            guard let est = i.estimatedDuration, let act = i.actualDuration, est >= 0, act >= 0 else { return false }
            guard let d = i.placementDate else { return false }
            return d >= start && d <= end
        }
        return DurationTotals(
            estimated: qualifying.reduce(0) { $0 + ($1.estimatedDuration ?? 0) },
            actual: qualifying.reduce(0) { $0 + ($1.actualDuration ?? 0) },
            count: qualifying.count
        )
    }

    /// Rated `TaskItem`s in the selected period, newest first, capped at `limit` —
    /// the Performance "Recent" list over the companion's population (DESIGN R2).
    public static func windowedRated(
        _ items: [TaskItem],
        period: PerformancePeriod,
        customStart: Date? = nil,
        now: Date = Date(),
        limit: Int = 10
    ) -> [TaskItem] {
        let (start, end) = dateRange(for: period, customStart: customStart, now: now)
        return items
            .filter { $0.rating != nil }
            .filter { i in
                guard let d = i.placementDate else { return false }
                return d >= start && d <= end
            }
            .sorted { ($0.placementDate ?? .distantPast) > ($1.placementDate ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// **Priority-weighted** average performance across the given tasks (0 if empty
    /// or zero total weight) — `Σ(rating·weight) / Σ(weight)` (DESIGN R7.3). With
    /// every weight `1` (equal weights) this is the plain mean.
    public static func average(_ tasks: [RatedSample]) -> Double {
        let totalWeight = tasks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let weightedSum = tasks.reduce(0.0) { $0 + Double($1.performanceRating) * $1.weight }
        return weightedSum / totalWeight
    }

    /// Bucket granularity for the trend chart, chosen from the window span so it
    /// stays within 12 buckets (Week→daily, Month→weekly, 3 Months→biweekly, up to
    /// 12mo→monthly, 36mo→quarterly, 72mo→half-year, else yearly).
    public static func granularity(
        for period: PerformancePeriod,
        tasks: [RatedSample] = [],
        customStart: Date? = nil,
        now: Date = Date()
    ) -> PerformanceGranularity {
        let cal = calendar
        let start = windowStart(for: period, customStart: customStart, tasks: tasks, now: now)
        let days = cal.dateComponents([.day], from: start, to: now).day ?? 0
        let months = cal.dateComponents([.month], from: start, to: now).month ?? 0
        if days <= 12 { return .daily }
        if days <= 62 { return .weekly }
        if days <= 168 { return .biweekly }   // ~3 months → biweekly
        if months <= 12 { return .monthly }
        if months <= 36 { return .quarterly }
        if months <= 72 { return .halfYear }
        return .yearly
    }

    /// Adaptive trend series (oldest → newest): the bucket size follows the
    /// selected period (daily / weekly / monthly), and the most recent bucket
    /// ends today. Each point averages the `performanceRating` of the tasks
    /// completed in its bucket.
    public static func trendSeries(
        _ tasks: [RatedSample],
        period: PerformancePeriod,
        cutoffs: PerformanceCutoffs = .defaults,
        customStart: Date? = nil,
        now: Date = Date()
    ) -> [PerformanceDataPoint] {
        let cal = calendar
        let gran = granularity(for: period, tasks: tasks, customStart: customStart, now: now)
        let start = windowStart(for: period, customStart: customStart, tasks: tasks, now: now)
        let count = bucketCount(granularity: gran, from: start, to: now, cal: cal)

        var points: [PerformanceDataPoint] = []
        for i in stride(from: count - 1, through: 0, by: -1) {
            let b = bucket(index: i, granularity: gran, now: now, cal: cal)
            let bucketTasks = tasks.filter { task in
                guard let d = task.completedAt else { return false }
                return d >= b.begin && d < b.end
            }
            let levelCounts = PerformanceLevel.allCases.map { level in
                LevelCount(level: level, count: bucketTasks.filter {
                    PerformancePreferencesService.level(for: $0.performanceRating, cutoffs: cutoffs) == level
                }.count)
            }
            points.append(PerformanceDataPoint(
                period: b.label,
                average: average(bucketTasks),
                taskCount: bucketTasks.count,
                levelCounts: levelCounts,
                trend: .stable
            ))
        }
        return applyTrends(points)
    }

    /// Best (max-average) point in a series, if any. Empty buckets (average 0
    /// with no tasks) are ignored so they can't win.
    public static func best(_ series: [PerformanceDataPoint]) -> PerformanceDataPoint? {
        series.filter { $0.taskCount > 0 }.max { $0.average < $1.average }
    }

    /// Overall trend comparing the last vs first *non-empty* bucket average.
    /// A percentage change (relative to the first bucket) within ±5% is Neutral.
    /// Empty buckets are skipped so a leading gap doesn't read as "Improving".
    public static func overallTrend(_ series: [PerformanceDataPoint]) -> String {
        let nonEmpty = series.filter { $0.taskCount > 0 }
        guard nonEmpty.count > 1, let first = nonEmpty.first, let last = nonEmpty.last else { return "N/A" }
        guard first.average != 0 else { return last.average > 0 ? "Improving" : "Neutral" }
        let percentChange = (last.average - first.average) / first.average * 100
        if percentChange > 5 { return "Improving" }
        if percentChange < -5 { return "Declining" }
        return "Neutral"
    }

    // MARK: - Helpers

    /// Start of the analysis window. For All Time this is the earliest completion
    /// so buckets don't stretch back to the epoch.
    private static func windowStart(
        for period: PerformancePeriod, customStart: Date?, tasks: [RatedSample], now: Date
    ) -> Date {
        if period == .allTime {
            return tasks.compactMap(\.completedAt).min() ?? now
        }
        return dateRange(for: period, customStart: customStart, now: now).start
    }

    /// The earliest instant the trend buckets actually cover (the begin of the
    /// oldest bucket). Buckets are anchored to `now`, so this — not the raw period
    /// start — is the true window edge that the stats must share with the chart.
    private static func alignedStart(
        for period: PerformancePeriod, tasks: [RatedSample], customStart: Date?, now: Date, cal: Calendar
    ) -> Date {
        let gran = granularity(for: period, tasks: tasks, customStart: customStart, now: now)
        let start = windowStart(for: period, customStart: customStart, tasks: tasks, now: now)
        let count = bucketCount(granularity: gran, from: start, to: now, cal: cal)
        return bucket(index: count - 1, granularity: gran, now: now, cal: cal).begin
    }

    /// Number of buckets covering `[start, now]` at the given granularity
    /// (clamped so the chart never shows more than 12 buckets).
    private static func bucketCount(
        granularity: PerformanceGranularity, from start: Date, to now: Date, cal: Calendar
    ) -> Int {
        let cap = 12
        let n: Int
        if let step = granularity.monthStep {
            let months = cal.dateComponents([.month], from: start, to: now).month ?? 0
            n = Int((Double(months) / Double(step)).rounded(.up))
        } else if granularity == .daily {
            n = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day ?? 0
        } else { // weekly / biweekly
            let days = cal.dateComponents([.day], from: start, to: now).day ?? 0
            n = Int((Double(days) / Double(granularity.dayStep ?? 7)).rounded(.up))
        }
        return max(1, min(cap, n))
    }

    /// The `i`-th most recent bucket (`i == 0` is the current one). Windows are
    /// half-open `[begin, end)`; month-based buckets are calendar-aligned.
    private static func bucket(
        index i: Int, granularity: PerformanceGranularity, now: Date, cal: Calendar
    ) -> (begin: Date, end: Date, label: String) {
        if let step = granularity.monthStep {
            let base = alignedMonthStart(now, step: step, cal: cal)
            let begin = cal.date(byAdding: .month, value: -i * step, to: base) ?? base
            let end = cal.date(byAdding: .month, value: step, to: begin) ?? begin
            return (begin, end, monthTierLabel(begin, granularity: granularity, cal: cal))
        }
        if granularity == .daily {
            let day = cal.date(byAdding: .day, value: -i, to: now) ?? now
            let begin = cal.startOfDay(for: day)
            let end = cal.date(byAdding: .day, value: 1, to: begin) ?? day
            return (begin, end, shortLabel(begin, format: "MMM d"))
        }
        // weekly / biweekly: rolling windows of `step` calendar days, the most
        // recent ending at the end of today (so the current bucket includes today).
        let step = granularity.dayStep ?? 7
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let end = cal.date(byAdding: .day, value: -step * i, to: endOfToday) ?? endOfToday
        let begin = cal.date(byAdding: .day, value: -step, to: end) ?? end
        // Label with the window's last included day (its end — today for the most
        // recent bucket), since `end` itself is the exclusive start of the next day.
        let lastDay = cal.date(byAdding: .day, value: -1, to: end) ?? begin
        return (begin, end, shortLabel(lastDay, format: "MMM d"))
    }

    /// First day of the `step`-month block containing `date` (e.g. calendar
    /// quarter / half / year start).
    private static func alignedMonthStart(_ date: Date, step: Int, cal: Calendar) -> Date {
        let c = cal.dateComponents([.year, .month], from: date)
        let absMonth = (c.year ?? 0) * 12 + ((c.month ?? 1) - 1)
        let aligned = (absMonth / step) * step
        var out = DateComponents()
        out.year = aligned / 12
        out.month = aligned % 12 + 1
        out.day = 1
        return cal.date(from: out) ?? date
    }

    /// Label for a month-based bucket beginning at `begin`.
    private static func monthTierLabel(_ begin: Date, granularity: PerformanceGranularity, cal: Calendar) -> String {
        switch granularity {
        case .quarterly:
            return shortLabel(begin, format: "QQQ ''yy")   // e.g. "Q3 '26"
        case .yearly:
            return shortLabel(begin, format: "yyyy")        // e.g. "2026"
        case .halfYear:
            let half = (cal.component(.month, from: begin) - 1) < 6 ? 1 : 2
            return "H\(half) \(shortLabel(begin, format: "''yy"))" // e.g. "H2 '26"
        default: // monthly — include year so names don't collide across years
            return shortLabel(begin, format: "MMM ''yy")    // e.g. "Jul '26"
        }
    }

    private static func applyTrends(_ points: [PerformanceDataPoint]) -> [PerformanceDataPoint] {
        guard points.count > 1 else { return points }
        var result = points
        for i in 1..<result.count {
            if result[i].average > result[i - 1].average { result[i].trend = .up }
            else if result[i].average < result[i - 1].average { result[i].trend = .down }
            else { result[i].trend = .stable }
        }
        return result
    }

    private static func shortLabel(_ date: Date, format: String) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = format
        return df.string(from: date)
    }
}
