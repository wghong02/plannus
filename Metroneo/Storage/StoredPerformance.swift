import Foundation
import SwiftData

/// SwiftData row for the performance **sidecar** (DESIGN R3.1) — the local
/// metadata attached to an Apple reminder, keyed by its stable external id.
///
/// A row is one of two kinds:
/// - a **normal** row keyed by a reminder's `externalId` (rating/notes/durations);
/// - an **occurrence snapshot** (`isOccurrence == true`, DESIGN R3.3) for one
///   completed occurrence of a recurring series, keyed by a composite
///   `"<seriesId>@<epoch>"` id. Occurrence rows carry a self-contained snapshot of
///   the series (title/list/priority) plus the occurrence's due + completion dates,
///   so they survive even if the series is later deleted, and are **exempt from
///   orphan reconciliation** (R3.2).
@Model
final class StoredPerformance {
    // No `@Attribute(.unique)` and a default value: SwiftData's CloudKit mirroring
    // (DESIGN — Sync) forbids unique constraints and requires every stored property
    // to be optional or defaulted. Uniqueness per id is enforced in code (see
    // `existingOrNew` / `recordOccurrence`).
    var reminderId: String = ""
    var rating: Int?
    var performanceNotes: String?
    var estimatedDuration: Int?
    var actualDuration: Int?

    // Occurrence-snapshot context — nil/false for normal rows (R3.3).
    var isOccurrence: Bool = false
    var seriesId: String?
    var seriesTitle: String?
    var seriesListId: String?
    var seriesPriorityRaw: Int?
    var occurrenceDate: Date?
    var occurrenceCompletionDate: Date?

    init(reminderId: String, rating: Int? = nil, performanceNotes: String? = nil,
         estimatedDuration: Int? = nil, actualDuration: Int? = nil) {
        self.reminderId = reminderId
        self.rating = rating
        self.performanceNotes = performanceNotes
        self.estimatedDuration = estimatedDuration
        self.actualDuration = actualDuration
    }
}
