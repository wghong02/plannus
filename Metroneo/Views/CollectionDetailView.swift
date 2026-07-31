import SwiftUI

/// A collection's members (DESIGN.md D5). An **ordered** collection shows its
/// `memberIds` sequence with drag-to-reorder; a **parallel** one shows members in
/// the active list sort (D5.5). Removing a row drops it from this collection only
/// — the entry survives (D5.6).
struct CollectionDetailView: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService

    let collectionId: String

    @State private var activeSheet: EntrySheet?

    private var collection: EntryCollection? {
        collectionService.collections.first { $0.id == collectionId }
    }

    private var members: [Entry] {
        guard let collection else { return [] }
        return CollectionMembers.resolve(collection, from: entryService.entries, sort: .timeAscending)
    }

    var body: some View {
        List {
            if members.isEmpty { Text("No entries in this collection").foregroundStyle(.secondary) }
            ForEach(members) { entry in
                EntryRow(entry: entry, onToggleComplete: { toggle(entry) })
                    .contentShape(Rectangle())
                    .onTapGesture { activeSheet = .edit(entry) }
            }
            .onMove(perform: move)
            .onDelete(perform: remove)
        }
        .navigationTitle(collection?.name ?? "Collection")
        .toolbar {
            if collection?.ordering == .ordered {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ordering", selection: orderingBinding) {
                        Text("Ordered").tag(CollectionOrdering.ordered)
                        Text("Parallel").tag(CollectionOrdering.parallel)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down.square") }
            }
        }
        .sheet(item: $activeSheet) { $0.view }
    }

    private var orderingBinding: Binding<CollectionOrdering> {
        Binding(
            get: { collection?.ordering ?? .parallel },
            set: { collectionService.setOrdering(id: collectionId, ordering: $0) }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        // `source`/`destination` index the displayed rows (`members`), which can
        // differ from raw `memberIds` when ids resolve to no live entry. Reorder
        // the visible id sequence and persist that, so the stored order matches
        // what the user dragged (and any dangling ids are dropped).
        var ids = members.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        collectionService.setMembers(collectionId: collectionId, ids: ids)
    }

    private func remove(at offsets: IndexSet) {
        for i in offsets { collectionService.removeMember(collectionId: collectionId, entryId: members[i].id) }
    }

    private func toggle(_ entry: Entry) {
        if entry.isCompleted {
            entryService.uncompleteEntry(id: entry.id)
        } else {
            activeSheet = .complete(entry)
        }
    }
}
