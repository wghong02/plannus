import WidgetKit
import SwiftUI

/// Widget 1 (DESIGN — Widgets): open reminders as rows with the leading complete
/// circle. Small + medium.
struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetroneoTasksWidget", provider: SnapshotProvider()) { entry in
            TasksWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks")
        .description("Your open reminders — tap the circle to complete one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    private var rowCount: Int { family == .systemSmall ? 3 : 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tasks", systemImage: "checklist").font(.caption.bold()).foregroundStyle(.secondary)
            if entry.snapshot.tasks.isEmpty {
                Spacer()
                Text("No open reminders").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.snapshot.tasks.prefix(rowCount)) { WidgetTaskRow(task: $0, completable: true) }
                Spacer(minLength: 0)
            }
        }
    }
}
