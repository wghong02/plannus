import Foundation
import SwiftData

/// SwiftData persistence models for the **v2** store — the storage mirror of the
/// value types ``Entry``, ``EntryCollection``, and ``Series`` (DESIGN.md D5/D6/D15).
/// The aspect/time structs are flattened into optional columns (with a presence
/// flag where "absent" and "present-but-empty" must be distinguished), so the
/// store stays natively queryable — no Objective-C, no `.xcdatamodeld`.

@Model
final class StoredEntry {
    @Attribute(.unique) var entryID: String
    var title: String
    var notes: String?
    var types: [String]
    var priorityRating: Int
    var createDate: Date
    var estimatedDuration: Int?
    var actualDuration: Int?

    // Schedule aspect — present iff `scheduledStart != nil` (start & end move together).
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var scheduledAllDay: Bool

    // Deadline aspect — present iff `deadlineDate != nil`.
    var deadlineDate: Date?
    var deadlineHasTime: Bool

    var reminderLeadMinutes: Int?

    // Completion aspect — `hasCompletion` distinguishes "not checkable" from
    // "checkable but not yet completed" (D6.2/D6.3).
    var hasCompletion: Bool
    var completedAt: Date?

    // Rating aspect — `hasRating` distinguishes "not ratable" from "ratable but
    // not yet rated" (D6.2/D6.3).
    var hasRating: Bool
    var performanceRating: Int?
    var performanceNotes: String?

    // Recurrence provenance (D15).
    var seriesID: String?
    var occurrenceIndex: Int?

    init(
        entryID: String,
        title: String,
        notes: String?,
        types: [String],
        priorityRating: Int,
        createDate: Date,
        estimatedDuration: Int?,
        actualDuration: Int?,
        scheduledStart: Date?,
        scheduledEnd: Date?,
        scheduledAllDay: Bool,
        deadlineDate: Date?,
        deadlineHasTime: Bool,
        reminderLeadMinutes: Int?,
        hasCompletion: Bool,
        completedAt: Date?,
        hasRating: Bool,
        performanceRating: Int?,
        performanceNotes: String?,
        seriesID: String?,
        occurrenceIndex: Int?
    ) {
        self.entryID = entryID
        self.title = title
        self.notes = notes
        self.types = types
        self.priorityRating = priorityRating
        self.createDate = createDate
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.scheduledAllDay = scheduledAllDay
        self.deadlineDate = deadlineDate
        self.deadlineHasTime = deadlineHasTime
        self.reminderLeadMinutes = reminderLeadMinutes
        self.hasCompletion = hasCompletion
        self.completedAt = completedAt
        self.hasRating = hasRating
        self.performanceRating = performanceRating
        self.performanceNotes = performanceNotes
        self.seriesID = seriesID
        self.occurrenceIndex = occurrenceIndex
    }
}

@Model
final class StoredEntryCollection {
    @Attribute(.unique) var collectionID: String
    var name: String
    var ordering: CollectionOrdering
    var memberIds: [String]

    init(collectionID: String, name: String, ordering: CollectionOrdering, memberIds: [String]) {
        self.collectionID = collectionID
        self.name = name
        self.ordering = ordering
        self.memberIds = memberIds
    }
}

@Model
final class StoredSeries {
    @Attribute(.unique) var seriesID: String
    /// JSON-encoded ``RecurrenceRule`` (an enum-with-payload — cleaner as `Data`).
    var ruleData: Data
    /// JSON-encoded template ``Entry`` — the canonical generator (D15.6 "All" edits it).
    var templateData: Data

    init(seriesID: String, ruleData: Data, templateData: Data) {
        self.seriesID = seriesID
        self.ruleData = ruleData
        self.templateData = templateData
    }
}
