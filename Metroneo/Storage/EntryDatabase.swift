import Foundation
import SwiftData

/// Row counts + connection state for the v2 entry store.
public struct EntryStoreStats: Equatable, Sendable {
    public var entryCount: Int
    public var collectionCount: Int
    public var seriesCount: Int
    public var schemaVersion: Int
    public var isClosed: Bool
}

/// SwiftData-backed persistence for the **v2** model — ``Entry`` (D6), grouped by
/// ``EntryCollection`` (D5), with recurrence ``Series`` (D15). Reuses
/// ``MetroneoError``.
///
/// Persistence is **per-entity** (D1): `upsertEntry`/`deleteEntry` write only the
/// affected row, never the whole set. Ids are unique UUIDs (D2), a non-empty
/// title is required and rejected — not coerced — on write (D3.2), `types`
/// round-trips as an array including `[]` (D4), and `deleteEntry` also drops the
/// id from every collection's `memberIds` (D5.6). Removal is always
/// object-by-object (D1.3).
public final class EntryDatabase {
    private let container: ModelContainer
    private let context: ModelContext

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// - Parameter inMemory: when true, an in-memory store (previews/tests, D-admin).
    public init(inMemory: Bool = false) throws {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let url = URL.applicationSupportDirectory.appending(path: "MetroneoV2.store")
            config = ModelConfiguration(url: url)
        }
        do {
            container = try ModelContainer(
                for: StoredEntry.self, StoredEntryCollection.self, StoredSeries.self,
                configurations: config
            )
        } catch {
            throw MetroneoError.database("Failed to load store: \(error)")
        }
        context = ModelContext(container)
    }

    // MARK: - Admin

    public func reset() throws {
        for row in try context.fetch(FetchDescriptor<StoredEntry>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<StoredEntryCollection>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<StoredSeries>()) { context.delete(row) }
        try context.save()
    }

    public func stats() -> EntryStoreStats {
        func count<T: PersistentModel>(_ type: T.Type) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return EntryStoreStats(
            entryCount: count(StoredEntry.self),
            collectionCount: count(StoredEntryCollection.self),
            seriesCount: count(StoredSeries.self),
            schemaVersion: 1,
            isClosed: false
        )
    }

    // MARK: - Entries

    public func loadEntries() throws -> [Entry] {
        let descriptor = FetchDescriptor<StoredEntry>(
            sortBy: [SortDescriptor(\.createDate, order: .reverse)]
        )
        return try context.fetch(descriptor).map(entry(from:))
    }

    /// Inserts-or-updates one entry by id (D1.1); other entries are untouched.
    /// Rejects an empty/whitespace title (D3.2) — no coercion.
    public func upsertEntry(_ entry: Entry) throws {
        guard !entry.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MetroneoError.validation("Entry title is required")
        }
        let row = try entryRow(id: entry.id) ?? {
            let new = StoredEntry(
                entryID: entry.id, title: entry.title, notes: nil, types: [],
                priorityRating: 50, createDate: entry.createDate,
                estimatedDuration: nil, actualDuration: nil,
                scheduledStart: nil, scheduledEnd: nil, scheduledAllDay: false,
                deadlineDate: nil, deadlineHasTime: false, reminderLeadMinutes: nil,
                hasCompletion: false, completedAt: nil,
                hasRating: false, performanceRating: nil, performanceNotes: nil,
                seriesID: nil, occurrenceIndex: nil
            )
            context.insert(new)
            return new
        }()
        apply(entry, to: row)
        try context.save()
    }

    /// Removes one entry (D1.2); unknown id is a no-op. Also drops the id from
    /// every collection's `memberIds` (D5.6), object-by-object.
    public func deleteEntry(id: String) throws {
        var changed = false
        if let row = try entryRow(id: id) {
            context.delete(row)
            changed = true
        }
        for collection in try context.fetch(FetchDescriptor<StoredEntryCollection>()) where collection.memberIds.contains(id) {
            collection.memberIds.removeAll { $0 == id }
            changed = true
        }
        if changed { try context.save() }
    }

    // MARK: - Collections

    public func loadCollections() throws -> [EntryCollection] {
        let descriptor = FetchDescriptor<StoredEntryCollection>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map(collection(from:))
    }

    public func upsertCollection(_ collection: EntryCollection) throws {
        let row = try collectionRow(id: collection.id) ?? {
            let new = StoredEntryCollection(
                collectionID: collection.id, name: collection.name,
                ordering: collection.ordering, memberIds: collection.memberIds
            )
            context.insert(new)
            return new
        }()
        row.name = collection.name
        row.ordering = collection.ordering
        row.memberIds = collection.memberIds
        try context.save()
    }

    /// Deletes the grouping only — member entries survive (D5.6). Unknown id no-op.
    public func deleteCollection(id: String) throws {
        if let row = try collectionRow(id: id) {
            context.delete(row)
            try context.save()
        }
    }

    // MARK: - Series

    public func loadSeries() throws -> [Series] {
        try context.fetch(FetchDescriptor<StoredSeries>()).compactMap(series(from:))
    }

    public func upsertSeries(_ series: Series) throws {
        let ruleData = try Self.encoder.encode(series.rule)
        let templateData = try Self.encoder.encode(series.template)
        let row = try seriesRow(id: series.id) ?? {
            let new = StoredSeries(seriesID: series.id, ruleData: ruleData, templateData: templateData)
            context.insert(new)
            return new
        }()
        row.ruleData = ruleData
        row.templateData = templateData
        try context.save()
    }

    public func deleteSeries(id: String) throws {
        if let row = try seriesRow(id: id) {
            context.delete(row)
            try context.save()
        }
    }

    // MARK: - Row lookups

    private func entryRow(id: String) throws -> StoredEntry? {
        var d = FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.entryID == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    private func collectionRow(id: String) throws -> StoredEntryCollection? {
        var d = FetchDescriptor<StoredEntryCollection>(predicate: #Predicate { $0.collectionID == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    private func seriesRow(id: String) throws -> StoredSeries? {
        var d = FetchDescriptor<StoredSeries>(predicate: #Predicate { $0.seriesID == id })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    // MARK: - Mapping

    private func apply(_ entry: Entry, to row: StoredEntry) {
        row.title = entry.title
        row.notes = entry.notes
        row.types = entry.types
        row.priorityRating = entry.priorityRating
        row.createDate = entry.createDate
        row.estimatedDuration = entry.estimatedDuration
        row.actualDuration = entry.actualDuration
        row.scheduledStart = entry.scheduled?.start
        row.scheduledEnd = entry.scheduled?.end
        row.scheduledAllDay = entry.scheduled?.allDay ?? false
        row.deadlineDate = entry.deadline?.date
        row.deadlineHasTime = entry.deadline?.hasTime ?? false
        row.reminderLeadMinutes = entry.reminderLeadMinutes
        row.hasCompletion = entry.completion != nil
        row.completedAt = entry.completion?.completedAt
        row.hasRating = entry.rating != nil
        row.performanceRating = entry.rating?.performanceRating
        row.performanceNotes = entry.rating?.performanceNotes
        row.seriesID = entry.seriesId
        row.occurrenceIndex = entry.occurrenceIndex
    }

    private func entry(from row: StoredEntry) -> Entry {
        let scheduled: Schedule? = row.scheduledStart.flatMap { start in
            row.scheduledEnd.map { end in Schedule(start: start, end: end, allDay: row.scheduledAllDay) }
        }
        let deadline: Deadline? = row.deadlineDate.map { Deadline(date: $0, hasTime: row.deadlineHasTime) }
        let completion: Completion? = row.hasCompletion ? Completion(completedAt: row.completedAt) : nil
        let rating: Rating? = row.hasRating
            ? Rating(performanceRating: row.performanceRating, performanceNotes: row.performanceNotes)
            : nil
        return Entry(
            id: row.entryID,
            title: row.title,
            notes: row.notes,
            types: row.types,
            priorityRating: row.priorityRating,
            createDate: row.createDate,
            estimatedDuration: row.estimatedDuration,
            actualDuration: row.actualDuration,
            scheduled: scheduled,
            deadline: deadline,
            reminderLeadMinutes: row.reminderLeadMinutes,
            completion: completion,
            rating: rating,
            seriesId: row.seriesID,
            occurrenceIndex: row.occurrenceIndex
        )
    }

    private func collection(from row: StoredEntryCollection) -> EntryCollection {
        EntryCollection(id: row.collectionID, name: row.name, ordering: row.ordering, memberIds: row.memberIds)
    }

    private func series(from row: StoredSeries) -> Series? {
        guard
            let rule = try? Self.decoder.decode(RecurrenceRule.self, from: row.ruleData),
            let template = try? Self.decoder.decode(Entry.self, from: row.templateData)
        else { return nil }
        return Series(id: row.seriesID, rule: rule, template: template)
    }
}
