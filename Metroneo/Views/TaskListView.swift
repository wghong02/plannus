import SwiftUI

/// Tasks tab (DESIGN.md §7, v2). Home for entries *and* collections via a
/// segmented **All entries ⇄ By collection** toggle. A leading filter control and
/// a trailing sort selector (D7.7/D7.8) drive the All-entries list; By-collection
/// browses collections (with an Ungrouped pseudo-group).
struct TaskListView: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var seriesService: SeriesService

    enum Mode: String, CaseIterable { case all = "All", byCollection = "Collections" }

    @State private var mode: Mode = .all
    @State private var sort: EntrySortOrder = .timeAscending
    @State private var filter = EntryFilter.none
    @State private var activeSheet: EntrySheet?
    @State private var pendingDelete: Entry?
    @State private var creatingCollection = false
    @State private var newCollectionName = ""

    private var visibleEntries: [Entry] {
        EntryQuery.sort(EntryQuery.filter(entryService.entries, with: filter), by: sort)
    }

    private var ungrouped: [Entry] {
        let grouped = Set(collectionService.collections.flatMap(\.memberIds))
        return visibleEntries.filter { !grouped.contains($0.id) }
    }

    private var allTags: [String] { Array(Set(entryService.entries.flatMap(\.types))).sorted() }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .all { allList } else { collectionList }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ToolbarItem(placement: .topBarLeading) {
                    FilterMenu(filter: $filter, tags: allTags, collections: collectionService.collections)
                }
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if mode == .all { activeSheet = .add(day: nil) } else { creatingCollection = true }
                    } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("addButton")
                }
            }
            .sheet(item: $activeSheet) { $0.view }
            .alert("New Collection", isPresented: $creatingCollection) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { collectionService.createCollection(name: name) }
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            .confirmationDialog(
                pendingDelete.map { "Delete “\($0.title)”?" } ?? "Delete entry?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) { deleteButtons }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Time ↑").tag(EntrySortOrder.timeAscending)
                Text("Time ↓").tag(EntrySortOrder.timeDescending)
                Text("A–Z").tag(EntrySortOrder.alphabetical)
            }
        } label: { Image(systemName: "arrow.up.arrow.down") }
    }

    // MARK: - All entries

    private var allList: some View {
        List {
            if visibleEntries.isEmpty {
                Text("No entries").foregroundStyle(.secondary)
            }
            ForEach(visibleEntries) { entry in
                entryRow(entry)
            }
        }
        .listStyle(.plain)
    }

    private func entryRow(_ entry: Entry) -> some View {
        EntryRow(entry: entry, onToggleComplete: { toggle(entry) })
            .contentShape(Rectangle())
            .onTapGesture { activeSheet = .edit(entry) }
            .contextMenu {
                Button("Edit") { activeSheet = .edit(entry) }
                if entry.isCompleted { Button("Edit Completion") { activeSheet = .edit(entry) } }
            }
            .swipeActions {
                Button(role: .destructive) { pendingDelete = entry } label: { Label("Delete", systemImage: "trash") }
            }
    }

    // MARK: - By collection

    private var collectionList: some View {
        List {
            Section {
                ForEach(collectionService.collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collectionId: collection.id)
                    } label: {
                        HStack {
                            Image(systemName: collection.ordering == .ordered ? "list.number" : "square.grid.2x2")
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.memberIds.count)").foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { collectionService.deleteCollection(id: collectionService.collections[i].id) }
                }
            } header: { Text("Collections") }

            if !ungrouped.isEmpty {
                Section("Ungrouped") {
                    ForEach(ungrouped) { entryRow($0) }
                }
            }
        }
    }

    // MARK: - Actions

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
