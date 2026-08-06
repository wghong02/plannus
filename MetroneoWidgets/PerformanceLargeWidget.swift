import WidgetKit
import SwiftUI

/// Widget 4 (DESIGN — Widgets): weekly performance **and** the week's rated reminders
/// together. Large.
struct PerformanceLargeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetroneoPerformanceLargeWidget", provider: SnapshotProvider()) { entry in
            PerformanceLargeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Performance & Ratings")
        .description("Your week's performance chart and the reminders you rated.")
        .supportedFamilies([.systemLarge])
    }
}

struct PerformanceLargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weekly performance", systemImage: "chart.bar.fill")
                .font(.caption.bold()).foregroundStyle(.secondary)
            WeeklySummary(snapshot: entry.snapshot)
            WeeklyBars(weekly: entry.snapshot.weekly, height: 70)

            Divider()

            Label("Rated this week", systemImage: "list.star")
                .font(.caption.bold()).foregroundStyle(.secondary)
            RatedList(items: entry.snapshot.recentRated, limit: 6)
            Spacer(minLength: 0)
        }
    }
}
