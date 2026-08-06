import SwiftUI

/// The companion Tasks tab (DESIGN R2/R5/R6): a **Needs rating** inbox pinned on
/// top, then one **expandable group per Reminders list**. Completing a reminder
/// writes back to Apple Reminders; tapping a needs-rating item opens the rating
/// sheet.
struct CompanionTasksView: View {
    @EnvironmentObject private var taskService: TaskService
    @State private var ratingItem: TaskItem?
    @State private var editingItem: TaskItem?
    @State private var showNewReminder = false
    /// Which list groups are expanded. A manual toggle (rather than `DisclosureGroup`)
    /// keeps each reminder row a real list row, so the leading complete circle stays
    /// individually tappable/discoverable.
    @State private var expandedLists: Set<String> = []

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
                    let expanded = expandedLists.contains(list.id)
                    Button {
                        if expanded { expandedLists.remove(list.id) } else { expandedLists.insert(list.id) }
                    } label: {
                        HStack {
                            Text(list.title).font(.headline).foregroundStyle(.primary)
                            Spacer()
                            Text("\(listItems.count)").foregroundStyle(.secondary)
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("listGroup-\(list.title)")

                    if expanded {
                        ForEach(listItems) { item in reminderRow(item) }
                    }
                }
            }

            Section {
                NavigationLink { BrowseCompletedView() } label: {
                    Label("Browse Completed", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("browseCompletedLink")
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
            // Leading complete circle — its own button so it stays independently
            // tappable/discoverable (a row-wide tap gesture would swallow it).
            Button {
                Task { await taskService.setCompleted(id: item.id, true) }
            } label: {
                Image(systemName: "circle").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("complete-\(item.title)")

            // Tapping the title area opens the editor.
            Button { editingItem = item } label: {
                VStack(alignment: .leading, spacing: 3) {
                    // Metroneo doesn't restyle overdue reminders — the Reminders app
                    // already badges/styles them, and a date-only reminder due today
                    // isn't overdue until the day ends (DESIGN Non-goals / Tasks).
                    Text(item.title).foregroundStyle(.primary)
                    if let due = item.dueDate {
                        // Subtitle shows the due date and, when set, its time.
                        Text(DateTimeUtilities.formatDeadline(due, hasTime: item.hasDueTime))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-\(item.title)")
        }
        // Trim the default nested-row indentation so the row sits flush-left.
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 16))
    }
}
