import SwiftUI

/// Browse Completed (DESIGN R6.5): every completed reminder (and recurring
/// occurrence) in the current list scope, newest first. **Tap** a row to open the
/// combined detail — the reminder's fields to **edit** on top and the **rating**
/// below (R4 + R6.2), one Save. **Swipe left** reveals **Edit** (left) and **Delete**
/// (right); swiping right does nothing. Recurring occurrence snapshots (R3.3) have
/// no live reminder, so they open the rating sheet only and have no swipe actions.
struct BrowseCompletedView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var prefs: PerformancePreferencesService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var items: [TaskItem] = []
    @State private var ratingItem: TaskItem?
    @State private var editingItem: TaskItem?

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("No completed reminders", systemImage: "clock.arrow.circlepath",
                                       description: Text("Reminders you complete here or in Apple Reminders show up here to rate."))
            } else {
                ForEach(items) { item in
                    Button { open(item) } label: { row(item) }
                        .accessibilityIdentifier("browseCompleted-\(item.title)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !item.isOccurrence {
                                // Declared trailing-edge first → Delete sits on the
                                // right, Edit to its left.
                                Button(role: .destructive) {
                                    Task { await taskService.delete(id: item.id); await reload() }
                                } label: { Label("Delete", systemImage: "trash") }
                                    .accessibilityIdentifier("deleteCompleted-\(item.title)")
                                Button { editingItem = item } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                                    .accessibilityIdentifier("editCompleted-\(item.title)")
                            }
                        }
                }
            }
        }
        .navigationTitle("Browse Completed")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .sheet(item: $ratingItem, onDismiss: { Task { await reload() } }) { RatingSheet(item: $0) }
        .sheet(item: $editingItem, onDismiss: { Task { await reload() } }) {
            CompanionReminderEditor(item: $0, includeRating: true)
        }
    }

    /// Occurrence snapshots have no editable reminder → rate only; everything else
    /// opens the combined edit-on-top / rate-below detail.
    private func open(_ item: TaskItem) {
        if item.isOccurrence { ratingItem = item } else { editingItem = item }
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
