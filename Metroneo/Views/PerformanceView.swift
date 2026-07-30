import SwiftUI

/// Performance tab (DESIGN.md §8, v2). The analytics math is unchanged ([PA-*]);
/// the population is now **rated entries** (D6.7), level display uses the custom
/// labels/colors (D8/D10), the overall trend uses the configurable thresholds/
/// labels (D12), and the leading filter scopes the analytics population (D7.7).
struct PerformanceView: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var prefs: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var period: PerformancePeriod = .month
    @State private var filter = EntryFilter.none

    private var scopedEntries: [Entry] { EntryQuery.filter(entryService.entries, with: filter) }
    private var samples: [RatedSample] { PerformanceAnalytics.samples(from: scopedEntries) }
    private var series: [PerformanceDataPoint] {
        PerformanceAnalytics.trendSeries(samples, period: period, cutoffs: prefs.cutoffs)
    }
    private var windowSamples: [RatedSample] {
        PerformanceAnalytics.filteredTasks(samples, period: period)
    }
    private var allTags: [String] { Array(Set(entryService.entries.flatMap(\.types))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(PerformancePeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    HStack {
                        stat("Rated", "\(windowSamples.count)")
                        Divider()
                        stat("Average", String(format: "%.1f", PerformanceAnalytics.average(windowSamples)))
                    }
                }

                Section("Trend") {
                    if series.allSatisfy({ $0.taskCount == 0 }) {
                        Text("No rated entries in this period").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                            bucketRow(point)
                        }
                    }
                }

                Section("Insights") {
                    LabeledContent("Best Period", value: PerformanceAnalytics.best(series)?.period ?? "—")
                    LabeledContent("Overall Trend", value: overallTrendText())
                }

                Section("Recent") {
                    let recent = recentRated()
                    if recent.isEmpty { Text("Nothing rated yet").foregroundStyle(.secondary) }
                    ForEach(recent) { entry in
                        HStack {
                            Text(entry.title)
                            Spacer()
                            levelBadge(entry.rating?.performanceRating ?? 0)
                        }
                    }
                }
            }
            .navigationTitle("Performance")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FilterMenu(filter: $filter, tags: allTags, collections: collectionService.collections)
                }
            }
        }
    }

    // MARK: - Pieces

    private func stat(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title2).bold()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func bucketRow(_ point: PerformanceDataPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(point.period).font(.caption)
                Spacer()
                Text(point.taskCount > 0 ? String(format: "%.0f", point.average) : "—")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(point.levelCounts, id: \.level) { lc in
                        if lc.count > 0 {
                            custom.color(for: lc.level)
                                .frame(width: max(2, geo.size.width * CGFloat(lc.count) / CGFloat(max(1, point.taskCount))))
                        }
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }

    private func levelBadge(_ rating: Int) -> some View {
        let level = prefs.level(for: rating)
        return Text(custom.label(for: level))
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(custom.color(for: level), in: Capsule())
            .foregroundStyle(custom.textColor(for: level))
    }

    private func overallTrendText() -> String {
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

    private func recentRated() -> [Entry] {
        scopedEntries
            .filter(\.isRated)
            .sorted { ($0.completion?.completedAt ?? $0.timeKey ?? .distantPast) > ($1.completion?.completedAt ?? $1.timeKey ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }
}
