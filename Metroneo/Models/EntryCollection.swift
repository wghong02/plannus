import Foundation

/// How a collection presents its members (D5.5).
/// - `ordered`: the `memberIds` sequence is the display order; supports drag-to-reorder.
/// - `parallel`: `memberIds` is an unordered set; members display in the active list sort (D7).
public enum CollectionOrdering: String, Codable, CaseIterable, Sendable {
    case ordered, parallel
}

/// A grouping of entries (D5). Named `EntryCollection` to avoid shadowing
/// `Swift.Collection`; the DESIGN.md spec calls it simply "Collection".
///
/// Membership is many-to-many and lives **only** here as `memberIds` (the single
/// source of truth, D5.3) — entries carry no back-reference. A collection is a
/// grouping, never a completable super-entry (D5.4). `memberIds` never holds
/// duplicates (D5.1 / COL-03).
public struct EntryCollection: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// Non-optional UUID (D2).
    public var id: String
    public var name: String
    public var ordering: CollectionOrdering
    public private(set) var memberIds: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        ordering: CollectionOrdering = .parallel,
        memberIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.ordering = ordering
        self.memberIds = Self.deduped(memberIds)
    }

    public func contains(_ entryId: String) -> Bool { memberIds.contains(entryId) }

    /// Appends an entry id (D5.1). Adding an already-present id is a **no-op** —
    /// no duplicate, no reposition (COL-03).
    public mutating func addMember(_ entryId: String) {
        guard !memberIds.contains(entryId) else { return }
        memberIds.append(entryId)
    }

    /// Drops an entry id if present (remove-from-collection, D5.6). No-op if absent.
    public mutating func removeMember(_ entryId: String) {
        memberIds.removeAll { $0 == entryId }
    }

    /// Reorders an **ordered** collection in one write (D5.2). An out-of-range
    /// source index or destination is a no-op (`Array.move` would otherwise trap).
    public mutating func moveMember(fromOffsets: IndexSet, toOffset: Int) {
        guard fromOffsets.allSatisfy({ memberIds.indices.contains($0) }),
              (0...memberIds.count).contains(toOffset) else { return }
        memberIds.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Replaces the whole membership (e.g. a reorder from a view), de-duplicated.
    public mutating func setMembers(_ ids: [String]) {
        memberIds = Self.deduped(ids)
    }

    /// Stable de-duplication preserving first-seen order.
    private static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
