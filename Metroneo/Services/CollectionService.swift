import Foundation
import Combine

/// Observable collection cache backed by an ``EntryDatabase`` (DESIGN.md D5).
///
/// Membership lives in each collection's `memberIds` (single source of truth,
/// D5.3); "which collections is entry X in" is **derived** here. Every mutation
/// is a per-entity write (D1) that updates the observable copy in place.
public final class CollectionService: ObservableObject {
    @Published public private(set) var collections: [EntryCollection] = []

    private let db: EntryDatabase

    public init(db: EntryDatabase) {
        self.db = db
    }

    @discardableResult
    public func loadCollections() -> [EntryCollection] {
        collections = (try? db.loadCollections()) ?? []
        return collections
    }

    // MARK: - Collection lifecycle

    @discardableResult
    public func createCollection(name: String, ordering: CollectionOrdering = .parallel) -> EntryCollection {
        let collection = EntryCollection(name: name, ordering: ordering)
        upsert(collection)
        return collection
    }

    public func renameCollection(id: String, name: String) {
        mutate(id) { $0.name = name }
    }

    public func setOrdering(id: String, ordering: CollectionOrdering) {
        mutate(id) { $0.ordering = ordering }
    }

    /// Deletes the grouping only — member entries survive (D5.6). Unknown id no-op.
    public func deleteCollection(id: String) {
        do {
            try db.deleteCollection(id: id)
        } catch {
            Log.entryError("Failed to delete collection: \(error)")
            return
        }
        collections.removeAll { $0.id == id }
    }

    // MARK: - Membership

    /// Adds an entry to a collection (de-duplicated, D5.1/COL-03).
    public func addMember(collectionId: String, entryId: String) {
        mutate(collectionId) { $0.addMember(entryId) }
    }

    /// Removes an entry from one collection; the entry itself survives (D5.6).
    public func removeMember(collectionId: String, entryId: String) {
        mutate(collectionId) { $0.removeMember(entryId) }
    }

    /// Reorders an ordered collection in one write (D5.2).
    public func reorder(collectionId: String, fromOffsets: IndexSet, toOffset: Int) {
        mutate(collectionId) { $0.moveMember(fromOffsets: fromOffsets, toOffset: toOffset) }
    }

    /// Replaces a collection's membership order (drag-reorder result).
    public func setMembers(collectionId: String, ids: [String]) {
        mutate(collectionId) { $0.setMembers(ids) }
    }

    /// Derived: the collections an entry belongs to (D5.3 — no back-reference).
    public func collections(containing entryId: String) -> [EntryCollection] {
        collections.filter { $0.contains(entryId) }
    }

    // MARK: - Helpers

    private func upsert(_ collection: EntryCollection) {
        do {
            try db.upsertCollection(collection)
        } catch {
            Log.entryError("Failed to upsert collection: \(error)")
            return
        }
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
        } else {
            collections.append(collection)
        }
    }

    private func mutate(_ id: String, _ change: (inout EntryCollection) -> Void) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        var updated = collections[index]
        change(&updated)
        upsert(updated)
    }
}
