import XCTest
@testable import Metroneo

/// Analytics math (unchanged from v1 — DESIGN.md §8 / PA-*), now over
/// ``RatedSample`` (population per D6.7).
final class PerformanceAnalyticsTests: XCTestCase {

    private func sample(_ rating: Int, _ completedKey: String) -> RatedSample {
        RatedSample(completedAt: day(completedKey), performanceRating: rating)
    }

    func testLevelClassification() {
        let c = PerformanceCutoffs.defaults
        XCTAssertEqual(PerformancePreferencesService.level(for: 95, cutoffs: c), .excellent)
        XCTAssertEqual(PerformancePreferencesService.level(for: 82, cutoffs: c), .veryGood)
        XCTAssertEqual(PerformancePreferencesService.level(for: 76, cutoffs: c), .good)
        XCTAssertEqual(PerformancePreferencesService.level(for: 61, cutoffs: c), .fair)
        XCTAssertEqual(PerformancePreferencesService.level(for: 30, cutoffs: c), .poor)
    }

    func testAverageAndFiltering() {
        let now = day("2026-07-21")
        let samples = [sample(80, "2026-07-20"), sample(40, "2026-01-01")]
        let filtered = PerformanceAnalytics.filteredTasks(samples, period: .week, now: now)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(PerformanceAnalytics.average(filtered), 80)
    }

    func testAverageOfEmptyIsZero() {
        XCTAssertEqual(PerformanceAnalytics.average([]), 0)
    }

    func testDateRangeOffsets() {
        let now = day("2026-07-22")
        let cal = Calendar.current
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .week, now: now).end, now)
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .week, now: now).start, cal.date(byAdding: .day, value: -7, to: now))
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .month, now: now).start, cal.date(byAdding: .month, value: -1, to: now))
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .year, now: now).start, cal.date(byAdding: .year, value: -1, to: now))
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .allTime, now: now).start, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(PerformanceAnalytics.dateRange(for: .custom, customStart: day("2026-01-01"), now: now).start, day("2026-01-01"))
    }

    func testFilteredCountMatchesTrendBuckets() {
        let now = day("2026-07-22")
        let samples = (0..<10).map { i in
            RatedSample(completedAt: Calendar.current.date(byAdding: .day, value: -i, to: now)!, performanceRating: 70)
        }
        for period in [PerformancePeriod.week, .month, .threeMonths] {
            let filtered = PerformanceAnalytics.filteredTasks(samples, period: period, now: now)
            let bucketTotal = PerformanceAnalytics.trendSeries(samples, period: period, now: now).reduce(0) { $0 + $1.taskCount }
            XCTAssertEqual(filtered.count, bucketTotal, "\(period): stat count and chart buckets cover the same samples")
        }
    }

    func testGranularityFollowsPeriod() {
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .week), .daily)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .month), .weekly)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .threeMonths), .biweekly)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .year), .monthly)
    }

    func testGranularityEscalatesForLongSpans() {
        let now = day("2026-07-22")
        func allTime(earliest key: String) -> PerformanceGranularity {
            PerformanceAnalytics.granularity(for: .allTime, tasks: [sample(70, key)], now: now)
        }
        XCTAssertEqual(allTime(earliest: "2025-07-01"), .monthly)
        XCTAssertEqual(allTime(earliest: "2024-01-01"), .quarterly)
        XCTAssertEqual(allTime(earliest: "2022-01-01"), .halfYear)
        XCTAssertEqual(allTime(earliest: "2005-01-01"), .yearly)
    }

    func testTrendSeriesBucketsByGranularity() {
        let now = day("2026-07-22")
        XCTAssertEqual(PerformanceAnalytics.trendSeries([], period: .week, now: now).count, 7)
        XCTAssertEqual(PerformanceAnalytics.trendSeries([], period: .year, now: now).count, 12)
    }

    func testTrendSeriesBucketsBySampleDate() {
        let now = day("2026-07-22")
        let samples = [sample(90, "2026-07-22")]
        let series = PerformanceAnalytics.trendSeries(samples, period: .week, now: now)
        XCTAssertEqual(series.last?.taskCount, 1)
        XCTAssertEqual(series.last?.average, 90)
        XCTAssertEqual(series.dropLast().reduce(0) { $0 + $1.taskCount }, 0)
    }

    func testWeeklyBucketLabelsUseEndDay() {
        let now = day("2026-07-23")
        let series = PerformanceAnalytics.trendSeries([], period: .month, now: now)
        XCTAssertEqual(series.last?.period, "Jul 23")
    }

    func testOverallTrendNeutralBand() {
        func pt(_ avg: Double) -> PerformanceDataPoint { PerformanceDataPoint(period: "\(avg)", average: avg, taskCount: 1, trend: .stable) }
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(80), pt(82)]), "Neutral")
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(80), pt(84)]), "Neutral")
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(80), pt(88)]), "Improving")
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(80), pt(72)]), "Declining")
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(0), pt(50)]), "Improving")
    }

    func testEmptyBucketsIgnoredInTrendAndBest() {
        func pt(_ avg: Double, _ count: Int) -> PerformanceDataPoint { PerformanceDataPoint(period: "\(avg)-\(count)", average: avg, taskCount: count, trend: .stable) }
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(0, 0), pt(80, 2), pt(80, 3)]), "Neutral")
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(0, 0), pt(60, 2), pt(90, 3)]), "Improving")
        XCTAssertEqual(PerformanceAnalytics.best([pt(0, 0), pt(60, 2), pt(90, 3)])?.average, 90)
        XCTAssertNil(PerformanceAnalytics.best([pt(0, 0), pt(0, 0)]))
        XCTAssertEqual(PerformanceAnalytics.overallTrend([pt(0, 0), pt(0, 0)]), "N/A")
    }

    func testTrendSeriesLevelCountsDistribution() {
        let now = day("2026-07-22")
        let ratings = [95, 82, 76, 61, 30]
        let samples = ratings.map { RatedSample(completedAt: now, performanceRating: $0) }

        let last = PerformanceAnalytics.trendSeries(samples, period: .week, now: now).last!
        XCTAssertEqual(last.taskCount, 5)
        let counts = Dictionary(uniqueKeysWithValues: last.levelCounts.map { ($0.level, $0.count) })
        XCTAssertEqual(counts[.excellent], 1)
        XCTAssertEqual(counts[.veryGood], 1)
        XCTAssertEqual(counts[.good], 1)
        XCTAssertEqual(counts[.fair], 1)
        XCTAssertEqual(counts[.poor], 1)

        let custom = PerformanceCutoffs(fair: 50, good: 60, veryGood: 70, excellent: 90)
        let lastCustom = PerformanceAnalytics.trendSeries(samples, period: .week, cutoffs: custom, now: now).last!
        let customCounts = Dictionary(uniqueKeysWithValues: lastCustom.levelCounts.map { ($0.level, $0.count) })
        XCTAssertEqual(customCounts[.veryGood], 2)
        XCTAssertEqual(customCounts[.good], 1)
        XCTAssertEqual(customCounts[.poor], 1)
    }

    func testGranularityForCustomPeriod() {
        let now = day("2026-07-22")
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .custom, customStart: day("2026-07-16"), now: now), .daily)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .custom, customStart: day("2026-06-01"), now: now), .weekly)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .custom, customStart: day("2026-04-01"), now: now), .biweekly)
        XCTAssertEqual(PerformanceAnalytics.granularity(for: .custom, customStart: day("2026-01-01"), now: now), .monthly)
    }

    // MARK: - Recent list scoping (windowedRated over TaskItems)

    func testWindowedRatedScopesToSelectedPeriod() {
        let now = day("2026-07-22")
        let items = [
            item(90, .none, "2026-07-20"),   // in week + month
            item(70, .none, "2026-07-01"),   // in month, not week
            item(50, .none, "2026-01-01"),   // older than both
            item(nil, .none, "2026-07-21"),  // unrated → excluded
        ]
        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .week, now: now).map(\.title),
                       ["2026-07-20"], "week keeps only in-week rated items")
        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .month, now: now).map(\.title),
                       ["2026-07-20", "2026-07-01"], "month is newest-first and in-window")
        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .allTime, now: now).map(\.title),
                       ["2026-07-20", "2026-07-01", "2026-01-01"], "allTime keeps every rated item; unrated excluded")
    }

    func testWindowedRatedRespectsLimit() {
        let now = day("2026-07-22")
        let items = (1...15).map { i -> TaskItem in
            let date = Calendar.current.date(byAdding: .day, value: -i, to: now)!
            let r = ReminderData(id: "e\(i)", title: "e\(i)", isCompleted: true, completionDate: date)
            return TaskItem(reminder: r, metadata: PerformanceMetadata(rating: 60))
        }
        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .allTime, now: now, limit: 5).count, 5)
    }

    // MARK: - Estimated vs Actual duration totals (D17)

    func testDurationTotalsSumsBothDurationsInWindow() { // spec: DUR-05
        let now = day("2026-07-22")
        let items = [
            item(nil, .none, "2026-07-20", estimated: 30, actual: 45), // both, in week + month
            item(nil, .none, "2026-07-01", estimated: 60, actual: 50), // both, in month only
            item(nil, .none, "2026-07-19", estimated: 20, actual: nil), // estimate only → excluded
            item(nil, .none, "2026-07-19", estimated: nil, actual: 40), // actual only → excluded
            item(nil, .none, "2026-01-01", estimated: 15, actual: 15), // both, older than a month
        ]

        let month = PerformanceAnalytics.durationTotals(items, period: .month, now: now)
        XCTAssertEqual(month.count, 2, "only items with both durations, in-window")
        XCTAssertEqual(month.estimated, 90)
        XCTAssertEqual(month.actual, 95)

        let week = PerformanceAnalytics.durationTotals(items, period: .week, now: now)
        XCTAssertEqual(week.count, 1, "week excludes the 3-weeks-ago item")
        XCTAssertEqual(week.estimated, 30)
        XCTAssertEqual(week.actual, 45)

        let all = PerformanceAnalytics.durationTotals(items, period: .allTime, now: now)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.estimated, 105)
        XCTAssertEqual(all.actual, 110)
    }

    func testDurationTotalsEmptyWhenNoneQualify() { // spec: DUR-05
        let now = day("2026-07-22")
        let items = [item(nil, .none, "2026-07-20", estimated: 30, actual: nil),
                     item(nil, .none, "2026-07-20", estimated: nil, actual: nil)]
        let totals = PerformanceAnalytics.durationTotals(items, period: .month, now: now)
        XCTAssertEqual(totals, DurationTotals(estimated: 0, actual: 0, count: 0))
    }

    // MARK: - Priority-weighted average + TaskItem population (DESIGNV2 R7.3 / R2)

    private func item(_ rating: Int?, _ priority: ReminderPriority, _ completedKey: String,
                      estimated: Int? = nil, actual: Int? = nil) -> TaskItem {
        let r = ReminderData(id: completedKey, title: completedKey, isCompleted: true,
                             completionDate: day(completedKey), priority: priority)
        return TaskItem(reminder: r, metadata: PerformanceMetadata(rating: rating, estimatedDuration: estimated, actualDuration: actual))
    }

    func testWeightedAverage() { // spec: R7.3
        func s(_ r: Int, _ w: Double) -> RatedSample { RatedSample(completedAt: nil, performanceRating: r, weight: w) }
        XCTAssertEqual(PerformanceAnalytics.average([s(40, 1), s(80, 1)]), 60, "equal weights → simple mean")
        XCTAssertEqual(PerformanceAnalytics.average([s(40, 1), s(80, 3)]), 70, "(40·1 + 80·3)/4")
        XCTAssertEqual(PerformanceAnalytics.average([s(50, 0)]), 0, "zero total weight → 0")
        XCTAssertEqual(PerformanceAnalytics.average([]), 0)
    }

    func testTaskItemSamplesCarryPriorityWeight() { // spec: R7.3 / R2.3
        let items = [item(40, .none, "2026-07-22"), item(80, .high, "2026-07-22"), item(nil, .low, "2026-07-22")]
        // Default weights None=1 / High=4 → (40·1 + 80·4)/5 = 72; unrated dropped.
        let samples = PerformanceAnalytics.samples(from: items)
        XCTAssertEqual(samples.count, 2, "only rated items map")
        XCTAssertEqual(PerformanceAnalytics.average(samples), 72)
        // Equal custom weights → plain mean 60.
        let equal = PerformanceAnalytics.samples(from: items, weights: PriorityWeights(none: 1, low: 1, medium: 1, high: 1))
        XCTAssertEqual(PerformanceAnalytics.average(equal), 60)
    }

    func testTrendAverageIsPriorityWeighted() { // spec: R7.3
        let now = day("2026-07-22")
        let samples = PerformanceAnalytics.samples(from: [item(40, .none, "2026-07-22"), item(80, .high, "2026-07-22")])
        let last = PerformanceAnalytics.trendSeries(samples, period: .week, now: now).last!
        XCTAssertEqual(last.taskCount, 2)
        XCTAssertEqual(last.average, 72, "the trend bucket average is priority-weighted")
    }

    func testTaskItemDurationTotalsAndWindowedRated() { // spec: R2 / D17
        let now = day("2026-07-22")
        let items = [
            item(90, .high, "2026-07-20", estimated: 30, actual: 45),
            item(70, .low, "2026-07-01"),
            item(nil, .none, "2026-07-20", estimated: 60, actual: nil), // no actual → not in durations
        ]
        let totals = PerformanceAnalytics.durationTotals(items, period: .month, now: now)
        XCTAssertEqual(totals, DurationTotals(estimated: 30, actual: 45, count: 1))

        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .week, now: now).map(\.title), ["2026-07-20"])
        XCTAssertEqual(PerformanceAnalytics.windowedRated(items, period: .month, now: now).map(\.title),
                       ["2026-07-20", "2026-07-01"], "newest first, rated only")
    }
}
