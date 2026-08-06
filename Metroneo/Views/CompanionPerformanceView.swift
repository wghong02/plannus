import SwiftUI
import Charts

/// Performance tab (DESIGN R2/R7, D16/D17): trend + distribution charts and
/// estimated-vs-actual bars over the **rated `TaskItem`s** joined from Apple
/// Reminders + the sidecar. The average is **priority-weighted** (R7.3) using the
/// configurable weights; analytics scope is set by Reminders list in Settings.
struct CompanionPerformanceView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var prefs: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var period: PerformancePeriod = .month
    @State private var customStart = Date()
    @State private var selectedPeriod: String?

    private struct Derived {
        let series: [PerformanceDataPoint]
        let windowSamples: [RatedSample]
        let granularity: PerformanceGranularity
        let recent: [TaskItem]
        let durations: DurationTotals

        var hasData: Bool { !series.allSatisfy { $0.taskCount == 0 } }
        var verticalXLabels: Bool { series.count > 8 }
    }

    private func computeDerived() -> Derived {
        let rated = taskService.ratedItems
        let samples = PerformanceAnalytics.samples(from: rated, weights: custom.priorityWeights)
        return Derived(
            series: PerformanceAnalytics.trendSeries(samples, period: period, cutoffs: prefs.cutoffs, customStart: customStart),
            windowSamples: PerformanceAnalytics.filteredTasks(samples, period: period, customStart: customStart),
            granularity: PerformanceAnalytics.granularity(for: period, tasks: samples, customStart: customStart),
            recent: PerformanceAnalytics.windowedRated(rated, period: period, customStart: customStart),
            durations: PerformanceAnalytics.durationTotals(rated, period: period, customStart: customStart)
        )
    }

    private var cutoffLines: [Int] {
        let c = prefs.cutoffs
        return [c.fair, c.good, c.veryGood, c.excellent]
    }

    var body: some View {
        let d = computeDerived()
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
        .pageBackground()
        .navigationTitle("Performance")
        .task { await taskService.refresh() }
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

    // MARK: - Trend card

    private func trendCard(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !d.hasData {
                Text("No rated reminders in this period")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("\(d.granularity.label) Performance").font(.headline)
                performanceChart(d.series, verticalXLabels: d.verticalXLabels)

                Text("Rated Reminders").font(.headline).padding(.top, 8)
                distributionChart(d.series, verticalXLabels: d.verticalXLabels)

                legend
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

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
            Text("Across \(d.count) time-tracked reminder\(d.count == 1 ? "" : "s") this period.")
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

    private func performanceChart(_ series: [PerformanceDataPoint], verticalXLabels: Bool) -> some View {
        Chart {
            ForEach(Array(cutoffLines.enumerated()), id: \.offset) { _, threshold in
                RuleMark(y: .value("Cutoff", Double(threshold)))
                    .foregroundStyle(custom.color(for: prefs.level(for: threshold)).opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            }
            ForEach(series.filter { $0.taskCount > 0 }, id: \.period) { point in
                LineMark(x: .value("Period", point.period), y: .value("Average", point.average))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Period", point.period), y: .value("Average", point.average))
                    .symbolSize(25)
                    .foregroundStyle(custom.color(for: prefs.level(for: Int(point.average))))
            }
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
            AxisValueLabel(orientation: vertical ? .vertical : .automatic,
                           verticalSpacing: vertical ? 8 : nil)
        }
    }

    private func yLabel(_ value: Int?) -> some AxisMark {
        AxisValueLabel {
            if let value { Text("\(value)").frame(width: 24, alignment: .trailing) }
        }
    }

    private func edgedPlot(_ plotArea: some View) -> some View {
        plotArea
            .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color(.separator)).frame(height: 1) }
    }

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
            Text("\(point.taskCount) reminder\(point.taskCount == 1 ? "" : "s")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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
                Text("Nothing rated in this period yet. Complete and rate reminders to see your performance data.")
                    .font(.subheadline).foregroundStyle(.secondary).padding()
            } else {
                ForEach(d.recent) { item in recentRow(item) }
            }
        }
    }

    private func recentRow(_ item: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.bold())
                if let date = item.placementDate {
                    Text(DateTimeUtilities.shortDate(date)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            levelBadge(item.rating ?? 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
