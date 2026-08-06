import WidgetKit
import SwiftUI

/// Widget 2 (DESIGN — Widgets): completed-but-unrated reminders as rows (no complete
/// circle — these are already done, awaiting a rating). Small + medium. Tapping the
/// widget opens the app to rate.
struct NeedsRatingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetroneoNeedsRatingWidget", provider: SnapshotProvider()) { entry in
            NeedsRatingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Needs Rating")
        .description("Completed reminders waiting for a rating.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NeedsRatingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    private var rowCount: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Needs rating", systemImage: "star").font(.caption.bold()).foregroundStyle(.secondary)
            if entry.snapshot.needsRating.isEmpty {
                Spacer()
                Text("All caught up").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.snapshot.needsRating.prefix(rowCount)) { WidgetTaskRow(task: $0) }
                Spacer(minLength: 0)
            }
        }
    }
}
