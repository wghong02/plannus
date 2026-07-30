import Foundation

/// Selectable list orders (D7.3). Extensible — add cases without touching the store.
public enum EntrySortOrder: String, CaseIterable, Sendable {
    case timeAscending, timeDescending, alphabetical
}

/// A list filter (D7.4). Facets combine with **AND** — an entry must satisfy
/// every active facet (SORT-06).
public struct EntryFilter: Equatable, Sendable {
    /// Completion facet. `nonCompletable` entries match **neither** upcoming nor
    /// completed, so they show only when this is `.any` (SORT-07).
    public enum CompletionState: Sendable { case any, upcoming, completed }

    public var completion: CompletionState
    public var tag: String?
    /// When set, only entries whose id is in this membership set pass (resolved by
    /// the caller from a collection's `memberIds`).
    public var collectionMemberIds: Set<String>?

    public init(completion: CompletionState = .any, tag: String? = nil, collectionMemberIds: Set<String>? = nil) {
        self.completion = completion
        self.tag = tag
        self.collectionMemberIds = collectionMemberIds
    }

    public static let none = EntryFilter()
}

/// Pure sort + filter for entry lists (D7). The store returns entries in any
/// stable order; the view applies the chosen sort + filter here (D7.6).
public enum EntryQuery {

    // MARK: - Filter (D7.4)

    public static func filter(_ entries: [Entry], with filter: EntryFilter) -> [Entry] {
        entries.filter { entry in
            switch filter.completion {
            case .any: break
            case .upcoming: if !(entry.isCompletable && !entry.isCompleted) { return false }
            case .completed: if !entry.isCompleted { return false }
            }
            if let tag = filter.tag, !entry.types.contains(tag) { return false }
            if let ids = filter.collectionMemberIds, !ids.contains(entry.id) { return false }
            return true
        }
    }

    // MARK: - Sort (D7.2 / D7.3)

    public static func sort(_ entries: [Entry], by order: EntrySortOrder) -> [Entry] {
        switch order {
        case .timeAscending: return sortedByTime(entries, ascending: true)
        case .timeDescending: return sortedByTime(entries, ascending: false)
        case .alphabetical: return entries.sorted(by: titleThenID)
        }
    }

    /// Timed entries by time key (asc/desc); **untimed always last** in both
    /// directions (D7.2/D7.3); ties break by title (case-insensitive) then id.
    private static func sortedByTime(_ entries: [Entry], ascending: Bool) -> [Entry] {
        let timed = entries.filter { !$0.isUntimed }
        let untimed = entries.filter { $0.isUntimed }
        let sortedTimed = timed.sorted { a, b in
            let ka = a.timeKey!, kb = b.timeKey!
            if ka != kb { return ascending ? ka < kb : ka > kb }
            return titleThenID(a, b)
        }
        return sortedTimed + untimed.sorted(by: titleThenID)
    }

    /// Stable tie-break: title A→Z (case-insensitive), then id.
    private static func titleThenID(_ a: Entry, _ b: Entry) -> Bool {
        let ta = a.title.lowercased(), tb = b.title.lowercased()
        if ta != tb { return ta < tb }
        return a.id < b.id
    }
}

/// Resolves a collection's members to display order (D5.5): an **ordered**
/// collection uses its `memberIds` sequence; a **parallel** one uses the active
/// D7 sort. Missing ids (deleted entries) are dropped.
public enum CollectionMembers {
    public static func resolve(_ collection: EntryCollection, from entries: [Entry], sort: EntrySortOrder) -> [Entry] {
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let resolved = collection.memberIds.compactMap { byId[$0] }
        return collection.ordering == .ordered ? resolved : EntryQuery.sort(resolved, by: sort)
    }
}
