import SwiftUI

/// Calendar tab (DESIGN.md §6, v2). A day picker drives the per-day entry list
/// from ``CalendarGrouping`` — completed entries render below incomplete ones,
/// and swipe-delete removes the whole entry behind a confirmation (a calendar row
/// is the entry, not just its appearance on that day).
struct CalendarView: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var seriesService: SeriesService

    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var filter = EntryFilter.none
    @State private var activeSheet: EntrySheet?
    @State private var pendingDelete: Entry?

    private var dayEntries: [Entry] {
        let filtered = EntryQuery.filter(entryService.entries, with: filter)
        return CalendarGrouping.entries(filtered, on: selectedDay)
    }

    private var allTags: [String] {
        Array(Set(entryService.entries.flatMap(\.types))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("", selection: $selectedDay, displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)

                List {
                    if dayEntries.isEmpty {
                        Text("No entries for this day")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(dayEntries) { entry in
                        EntryRow(entry: entry, onToggleComplete: { toggle(entry) })
                            .contentShape(Rectangle())
                            .onTapGesture { activeSheet = .edit(entry) }
                            .swipeActions {
                                Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FilterMenu(filter: $filter, tags: allTags, collections: collectionService.collections)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { activeSheet = .add(day: selectedDay) } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $activeSheet) { $0.view }
            .confirmationDialog(
                pendingDelete.map { "Delete “\($0.title)”?" } ?? "Delete entry?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                deleteButtons
            } message: {
                Text("This removes the entry from every day and collection.")
            }
        }
    }

    @ViewBuilder private var deleteButtons: some View {
        if let entry = pendingDelete {
            if entry.isSeriesMember {
                Button("Delete This", role: .destructive) { seriesService.delete(entry, scope: .thisOnly); pendingDelete = nil }
                Button("Delete This & Future", role: .destructive) { seriesService.delete(entry, scope: .thisAndFuture); pendingDelete = nil }
                Button("Delete All in Series", role: .destructive) { seriesService.delete(entry, scope: .all); pendingDelete = nil }
            } else {
                Button("Delete", role: .destructive) { entryService.deleteEntry(id: entry.id); pendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func toggle(_ entry: Entry) {
        if entry.isCompleted {
            entryService.uncompleteEntry(id: entry.id)
        } else {
            activeSheet = .complete(entry)
        }
    }
}
