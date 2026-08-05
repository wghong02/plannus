import SwiftUI
import Charts

/// Performance tab (DESIGN.md §8 + D16). The analytics math is unchanged ([PA-*]);
/// the population is **rated entries** (D6.7), and the trend renders as two stacked
/// Swift Charts plots — a monotone average line with cutoff reference lines, and a
/// stacked distribution bar — using the custom labels (D8) and colors (D10). The
/// leading filter scopes the analytics population (D7.7).
struct PerformanceView: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var prefs: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var period: PerformancePeriod = .month
    @State private var customStart = Date()
    @State private var filter = EntryFilter.none
    @State private var selectedPeriod: String?

    /// All the period-scoped analytics the body needs, computed **once** per
    /// render (see `computeDerived`) so the trend pipeline and its inputs aren't
    /// rebuilt on every sub-view access.
    private struct Derived {
        let series: [PerformanceDataPoint]
        let windowSamples: [RatedSample]
        let granularity: PerformanceGranularity
        let recent: [Entry]
        let durations: DurationTotals

        /// At least one bucket has entries (empty ⇒ the placeholder message).
        var hasData: Bool { !series.allSatisfy { $0.taskCount == 0 } }
        /// Rotate x labels vertical once the axis gets crowded (D16.6).
        var verticalXLabels: Bool { series.count > 8 }
        var periods: [String] { series.map(\.period) }
    }

    private func computeDerived() -> Derived {
        let scoped = EntryQuery.filter(entryService.entries, with: filter)
        let samples = PerformanceAnalytics.samples(from: scoped)
        return Derived(
            series: PerformanceAnalytics.trendSeries(samples, period: period, cutoffs: prefs.cutoffs, customStart: customStart),
            windowSamples: PerformanceAnalytics.filteredTasks(samples, period: period, customStart: customStart),
            granularity: PerformanceAnalytics.granularity(for: period, tasks: samples, customStart: customStart),
            recent: PerformanceAnalytics.windowedRated(scoped, period: period, customStart: customStart),
            durations: PerformanceAnalytics.durationTotals(scoped, period: period, customStart: customStart)
        )
    }

    /// Rating thresholds drawn as reference lines (D16.2).
    private var cutoffLines: [Int] {
        let c = prefs.cutoffs
        return [c.fair, c.good, c.veryGood, c.excellent]
    }
    private var allTags: [String] { Array(Set(entryService.entries.flatMap(\.types))).sorted() }

    var body: some View {
        let d = computeDerived()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    periodSelector

                    HStack {
                        statCard("Rated", "\(d.windowSamples.count)")
                        statCard("Average", String(format: "%.1f", PerformanceAnalytics.average(d.windowSamples)))
                    }

                    Divider()

                    Text("Trends").font(.title3.bold())
                    trendCard(d)
                    if d.durations.count > 0 { durationCard(d.durations) }
                    insights(d)
                    recentList(d)
                }
                .padding()
            }
            .navigationTitle("Performance")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FilterMenu(filter: $filter, tags: allTags, collections: collectionService.collections)
                }
            }
        }
    }

    // MARK: - Period + stats

    private var periodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Period", selection: $period) {
                ForEach(PerformancePeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if period == .custom {
                DatePicker("Start date", selection: $customStart, in: ...Date(), displayedComponents: .date)
                    .padding(.top, 12)
                    .accessibilityIdentifier("customStartPicker")
            }
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: 32, weight: .bold)).foregroundStyle(.blue)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .cardStyle()
    }

    // MARK: - Trend card (D16)

    private func trendCard(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !d.hasData {
                Text("No rated entries in this period")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("\(d.granularity.label) Performance").font(.headline)
                performanceChart(d.series, verticalXLabels: d.verticalXLabels)

                Text("Rated Entries").font(.headline).padding(.top, 8)
                distributionChart(d.series, verticalXLabels: d.verticalXLabels)

                legend
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Estimated vs Actual time (D17)

    /// Two bars — total estimated vs total actual minutes across the period's
    /// time-tracked entries (those with both durations). Shown only when there's
    /// at least one such entry (`durations.count > 0`).
    private func durationCard(_ d: DurationTotals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated vs Actual").font(.headline)
            Chart {
                ForEach(durationBars(d), id: \.label) { bar in
                    BarMark(x: .value("Kind", bar.label), y: .value("Minutes", bar.minutes))
                        .foregroundStyle(bar.color)
                        .annotation(position: .top) {
                            Text(DateTimeUtilities.formatDuration(bar.minutes)).font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { yLabel($0.as(Int.self)) } }
            .chartPlotStyle { edgedPlot($0) }
            .frame(height: 150)
            Text("Across \(d.count) time-tracked \(d.count == 1 ? "entry" : "entries") this period.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("durationCard")
    }

    private func durationBars(_ d: DurationTotals) -> [(label: String, minutes: Int, color: Color)] {
        [("Estimated", d.estimated, .blue), ("Actual", d.actual, .orange)]
    }

    /// Top plot: average line (0–100) with dashed cutoff reference lines (D16.1/2/5).
    private func performanceChart(_ series: [PerformanceDataPoint], verticalXLabels: Bool) -> some View {
        Chart {
            // `enumerated` ids avoid a duplicate-id ForEach when two cutoffs coincide
            // (the editor permits equal thresholds).
            ForEach(Array(cutoffLines.enumerated()), id: \.offset) { _, threshold in
                RuleMark(y: .value("Cutoff", Double(threshold)))
                    .foregroundStyle(custom.color(for: prefs.level(for: threshold)).opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            }
            // Only plot buckets with entries; empty buckets stay a gap, not a 0.
            ForEach(series.filter { $0.taskCount > 0 }, id: \.period) { point in
                LineMark(x: .value("Period", point.period), y: .value("Average", point.average))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Period", point.period), y: .value("Average", point.average))
                    .symbolSize(25)
                    .foregroundStyle(custom.color(for: prefs.level(for: Int(point.average))))
            }
            // Callout only over buckets that actually have data — never an empty
            // bucket (which would read as a real "Avg 0").
            if let selectedPeriod,
               let point = series.first(where: { $0.period == selectedPeriod && $0.taskCount > 0 }) {
                RuleMark(x: .value("Period", selectedPeriod))
                    .foregroundStyle(.gray.opacity(0.4))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCallout(point)
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: series.map(\.period))
        .chartXSelection(value: $selectedPeriod)
        .chartXAxis { crowdAwareXLabels(verticalXLabels) }
        .chartYAxis { AxisMarks(position: .leading) { yLabel($0.as(Double.self).map { Int($0) }) } }
        .chartPlotStyle { edgedPlot($0) }
        .frame(height: 170)
    }

    /// Bottom plot: entry count per bucket, stacked by performance category (D16.3).
    private func distributionChart(_ series: [PerformanceDataPoint], verticalXLabels: Bool) -> some View {
        Chart {
            ForEach(series, id: \.period) { point in
                ForEach(point.levelCounts, id: \.level) { lc in
                    if lc.count > 0 {
                        BarMark(x: .value("Period", point.period), y: .value("Count", lc.count))
                            .foregroundStyle(custom.color(for: lc.level))
                    }
                }
            }
        }
        .chartXScale(domain: series.map(\.period))
        .chartXAxis { crowdAwareXLabels(verticalXLabels) }
        .chartYAxis { AxisMarks(position: .leading) { yLabel($0.as(Int.self)) } }
        .chartPlotStyle { edgedPlot($0) }
        .frame(height: 110)
    }

    private func crowdAwareXLabels(_ vertical: Bool) -> some AxisContent {
        AxisMarks {
            AxisValueLabel(
                orientation: vertical ? .vertical : .automatic,
                verticalSpacing: vertical ? 8 : nil
            )
        }
    }

    /// Fixed-width y label so the two stacked plots' plot areas line up (D16.6).
    private func yLabel(_ value: Int?) -> some AxisMark {
        AxisValueLabel {
            if let value { Text("\(value)").frame(width: 24, alignment: .trailing) }
        }
    }

    /// Left + bottom axis lines, no interior grid (D16.6).
    private func edgedPlot(_ plotArea: some View) -> some View {
        plotArea
            .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color(.separator)).frame(height: 1) }
    }

    /// Category key using the custom labels + colors (D16.4).
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(PerformanceLevel.allCases, id: \.self) { level in
                HStack(spacing: 4) {
                    Circle().fill(custom.color(for: level)).frame(width: 8, height: 8)
                    Text(custom.label(for: level)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.7)
    }

    private func selectionCallout(_ point: PerformanceDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.period).font(.caption2.bold())
            Text("Avg \(String(format: "%.0f", point.average))")
                .font(.caption2)
                .foregroundStyle(custom.color(for: prefs.level(for: Int(point.average))))
            Text("\(point.taskCount) entr\(point.taskCount == 1 ? "y" : "ies")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
    }

    // MARK: - Insights + recent

    private func insights(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Insights").font(.headline)
            HStack {
                insightItem("Best Period", PerformanceAnalytics.best(d.series)?.period ?? "N/A")
                insightItem("Overall Trend", overallTrendText(d.series))
                insightItem("Best Rating", d.windowSamples.map(\.performanceRating).max().map { "\($0)" } ?? "N/A")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func insightItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity)
    }

    private func recentList(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Performance").font(.title3.bold())
            if d.recent.isEmpty {
                Text("Nothing rated in this period yet. Complete and rate entries to see your performance data.")
                    .font(.subheadline).foregroundStyle(.secondary).padding()
            } else {
                ForEach(d.recent) { entry in recentRow(entry) }
            }
        }
    }

    private func recentRow(_ entry: Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.subheadline.bold())
                if let date = entry.completion?.completedAt ?? entry.timeKey {
                    Text(DateTimeUtilities.shortDate(date)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            levelBadge(entry.rating?.performanceRating ?? 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func levelBadge(_ rating: Int) -> some View {
        let level = prefs.level(for: rating)
        return Text(custom.label(for: level))
            .font(.caption2.bold())
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(custom.color(for: level), in: Capsule())
            .foregroundStyle(custom.textColor(for: level))
    }

    private func overallTrendText(_ series: [PerformanceDataPoint]) -> String {
        let nonEmpty = series.filter { $0.taskCount > 0 }
        guard nonEmpty.count > 1, let first = nonEmpty.first, let last = nonEmpty.last else {
            return custom.trendLabel(\.na)
        }
        switch TrendClassifier.classify(
            firstAverage: first.average, lastAverage: last.average,
            improvingPercent: custom.trendImprovingPercent, decliningPercent: custom.trendDecliningPercent
        ) {
        case .improving: return custom.trendLabel(\.improving)
        case .declining: return custom.trendLabel(\.declining)
        case .neutral: return custom.trendLabel(\.neutral)
        }
    }
}
