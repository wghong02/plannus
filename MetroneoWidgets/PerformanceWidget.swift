import WidgetKit
import SwiftUI
import AppIntents

/// Widget 3 (DESIGN — Widgets): weekly performance **or** the week's rated reminders,
/// with an interactive **toggle** (AppIntent) to switch between them. Medium.
struct PerformanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetroneoPerformanceWidget", provider: SnapshotProvider()) { entry in
            PerformanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weekly Performance")
        .description("Your week's performance, or the reminders you rated — tap to switch.")
        .supportedFamilies([.systemMedium])
    }
}

struct PerformanceWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(entry.showRated ? "Rated this week" : "Weekly performance",
                      systemImage: entry.showRated ? "list.star" : "chart.bar.fill")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                // The switch: flips the shared mode and reloads.
                Button(intent: TogglePerformanceModeIntent()) {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            if entry.showRated {
                RatedList(items: entry.snapshot.recentRated, limit: 4)
                Spacer(minLength: 0)
            } else {
                WeeklySummary(snapshot: entry.snapshot)
                WeeklyBars(weekly: entry.snapshot.weekly, height: 48)
            }
        }
    }
}
