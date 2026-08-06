import SwiftUI

/// Browse Completed (DESIGN R6.5): every completed reminder (and recurring
/// occurrence) in the current list scope, newest first, tappable to open the same
/// rating sheet — so any completed reminder can be rated on demand, including ones
/// finished before the Needs-rating look-back window (R6.1a).
struct BrowseCompletedView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var prefs: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var items: [TaskItem] = []
    @State private var ratingItem: TaskItem?

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("No completed reminders", systemImage: "clock.arrow.circlepath",
                                       description: Text("Reminders you complete here or in Apple Reminders show up here to rate."))
            } else {
                ForEach(items) { item in
                    Button { ratingItem = item } label: { row(item) }
                        .accessibilityIdentifier("browseCompleted-\(item.title)")
                }
            }
        }
        .navigationTitle("Browse Completed")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(item: $ratingItem, onDismiss: { Task { await reload() } }) { RatingSheet(item: $0) }
    }

    private func row(_ item: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).foregroundStyle(.primary)
                if let date = item.completionDate {
                    Text("Completed \(DateTimeUtilities.shortDate(date))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let rating = item.rating {
                Text(custom.label(for: prefs.level(for: rating)))
                    .font(.caption2.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(custom.color(for: prefs.level(for: rating)), in: Capsule())
                    .foregroundStyle(custom.textColor(for: prefs.level(for: rating)))
            } else {
                Text("Tap to rate").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func reload() async { items = await taskService.browseCompleted() }
}
