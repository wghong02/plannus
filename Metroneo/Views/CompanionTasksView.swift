import SwiftUI

/// The companion Tasks tab (DESIGNV2 R2/R5/R6): a **Needs rating** inbox pinned on
/// top, then one **expandable group per Reminders list**. Completing a reminder
/// writes back to Apple Reminders; tapping a needs-rating item opens the rating
/// sheet.
struct CompanionTasksView: View {
    @EnvironmentObject private var taskService: TaskService
    @State private var ratingItem: TaskItem?
    @State private var editingItem: TaskItem?
    @State private var showNewReminder = false

    var body: some View {
        List {
            if !taskService.needsRating.isEmpty {
                Section("Needs rating") {
                    ForEach(taskService.needsRating) { item in
                        Button { ratingItem = item } label: { needsRatingRow(item) }
                            .accessibilityIdentifier("needsRating-\(item.title)")
                    }
                }
            }

            ForEach(taskService.lists) { list in
                let listItems = taskService.items.filter { $0.listId == list.id }
                if !listItems.isEmpty {
                    DisclosureGroup {
                        ForEach(listItems) { item in reminderRow(item) }
                    } label: {
                        HStack {
                            Text(list.title).font(.headline)
                            Spacer()
                            Text("\(listItems.count)").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("listGroup-\(list.title)")
                }
            }
        }
        .overlay {
            if taskService.items.isEmpty && taskService.needsRating.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "checklist",
                                       description: Text("Reminders you add here or in Apple Reminders show up together."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewReminder = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("addReminderButton")
            }
        }
        .task { await taskService.refresh() }
        .refreshable { await taskService.refresh() }
        .sheet(item: $ratingItem) { RatingSheet(item: $0) }
        .sheet(item: $editingItem) { CompanionReminderEditor(item: $0) }
        .sheet(isPresented: $showNewReminder) { CompanionReminderEditor() }
    }

    private func needsRatingRow(_ item: TaskItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).foregroundStyle(.primary)
                Text("Completed — tap to rate").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "star").foregroundStyle(.orange)
        }
    }

    private func reminderRow(_ item: TaskItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await taskService.setCompleted(id: item.id, true) }
            } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("complete-\(item.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    // Overdue, still-open reminders read red (matches Apple).
                    .foregroundStyle(isOverdue(item) ? Color.red : Color.primary)
                if let due = item.dueDate {
                    Text(DateTimeUtilities.shortDate(due)).font(.caption)
                        .foregroundStyle(isOverdue(item) ? Color.red.opacity(0.8) : Color.secondary)
                }
            }
            Spacer()
        }
        // Tapping the row (outside the complete toggle) opens the editor.
        .contentShape(Rectangle())
        .onTapGesture { editingItem = item }
    }

    private func isOverdue(_ item: TaskItem) -> Bool {
        guard let due = item.dueDate else { return false }
        return !item.isCompleted && due < Date()
    }
}
