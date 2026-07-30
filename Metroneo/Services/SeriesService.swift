import Foundation
import Combine

/// The scope an edit/delete applies to within a recurring series (D15.6).
public enum SeriesScope: Sendable {
    case thisOnly, thisAndFuture, all
}

/// Owns recurring ``Series`` and their pre-generated occurrences (DESIGN.md D15).
///
/// Creating a series materializes every occurrence up front as an independent
/// ``Entry`` (D15.2). Edit/delete offer the three scopes (D15.6): *this* detaches
/// the occurrence, *this-and-future* regenerates from here, *all* edits the
/// template and regenerates. Occurrence generation is delegated to the pure
/// ``RecurrenceEngine``; entry writes go through ``EntryService``.
public final class SeriesService: ObservableObject {
    @Published public private(set) var series: [Series] = []

    private let db: EntryDatabase
    private let entries: EntryService

    public init(db: EntryDatabase, entries: EntryService) {
        self.db = db
        self.entries = entries
    }

    @discardableResult
    public func loadSeries() -> [Series] {
        series = (try? db.loadSeries()) ?? []
        return series
    }

    /// Creates a series from a `template` + `rule` and inserts all occurrences.
    @discardableResult
    public func createSeries(template: Entry, rule: RecurrenceRule) -> Series {
        var baseline = template
        baseline.seriesId = nil
        baseline.occurrenceIndex = nil
        let newSeries = Series(rule: rule, template: baseline)
        persist(newSeries)
        for occurrence in RecurrenceEngine.generate(series: newSeries) {
            entries.upsertEntry(occurrence)
        }
        return newSeries
    }

    // MARK: - Delete (D15.6)

    public func delete(_ entry: Entry, scope: SeriesScope) {
        guard let seriesId = entry.seriesId else {
            entries.deleteEntry(id: entry.id)
            return
        }
        switch scope {
        case .thisOnly:
            entries.deleteEntry(id: entry.id)
        case .thisAndFuture:
            let fromIndex = entry.occurrenceIndex ?? 0
            for occurrence in occurrences(of: seriesId) where (occurrence.occurrenceIndex ?? 0) >= fromIndex {
                entries.deleteEntry(id: occurrence.id)
            }
        case .all:
            for occurrence in occurrences(of: seriesId) {
                entries.deleteEntry(id: occurrence.id)
            }
            deleteSeriesRecord(seriesId)
        }
        pruneIfEmpty(seriesId)
    }

    // MARK: - Edit (D15.6)

    public func edit(_ edited: Entry, scope: SeriesScope) {
        guard let seriesId = edited.seriesId else {
            entries.upsertEntry(edited)
            return
        }
        switch scope {
        case .thisOnly:
            // Detach: this occurrence leaves the series and becomes a one-off.
            var detached = edited
            detached.seriesId = nil
            detached.occurrenceIndex = nil
            entries.upsertEntry(detached)
            pruneIfEmpty(seriesId)

        case .all:
            guard var current = series.first(where: { $0.id == seriesId }) else {
                entries.upsertEntry(edited)
                return
            }
            // Propagate the edited shared fields onto the template, keeping the
            // template's own date pattern; then regenerate every occurrence.
            current.template = mergedTemplate(base: current.template, edits: edited)
            persist(current)
            regenerate(current)

        case .thisAndFuture:
            guard let current = series.first(where: { $0.id == seriesId }) else {
                entries.upsertEntry(edited)
                return
            }
            let fromIndex = edited.occurrenceIndex ?? 0
            let remaining = occurrences(of: seriesId).filter { ($0.occurrenceIndex ?? 0) >= fromIndex }.count
            for occurrence in occurrences(of: seriesId) where (occurrence.occurrenceIndex ?? 0) >= fromIndex {
                entries.deleteEntry(id: occurrence.id)
            }
            // Spin up a new series starting at the edited occurrence's dates.
            var newTemplate = edited
            newTemplate.seriesId = nil
            newTemplate.occurrenceIndex = nil
            let newRule = RecurrenceRule(
                frequency: current.rule.frequency,
                interval: current.rule.interval,
                end: .afterCount(max(1, remaining))
            )
            _ = createSeries(template: newTemplate, rule: newRule)
            pruneIfEmpty(seriesId)
        }
    }

    // MARK: - Helpers

    private func occurrences(of seriesId: String) -> [Entry] {
        entries.entries
            .filter { $0.seriesId == seriesId }
            .sorted { ($0.occurrenceIndex ?? 0) < ($1.occurrenceIndex ?? 0) }
    }

    /// Deletes all current occurrences and regenerates from the stored template.
    private func regenerate(_ series: Series) {
        for occurrence in occurrences(of: series.id) {
            entries.deleteEntry(id: occurrence.id)
        }
        for occurrence in RecurrenceEngine.generate(series: series) {
            entries.upsertEntry(occurrence)
        }
    }

    /// Copies the edited entry's shared fields onto `base`, keeping `base`'s dates
    /// and provenance (so an "All" edit doesn't shift the series' schedule).
    private func mergedTemplate(base: Entry, edits: Entry) -> Entry {
        var t = base
        t.title = edits.title
        t.notes = edits.notes
        t.types = edits.types
        t.priorityRating = edits.priorityRating
        t.estimatedDuration = edits.estimatedDuration
        t.reminderLeadMinutes = edits.reminderLeadMinutes
        t.completion = edits.completion.map { _ in Completion() } // keep on/off, reset value
        t.rating = edits.rating.map { _ in Rating() }
        return t
    }

    private func persist(_ series: Series) {
        do {
            try db.upsertSeries(series)
        } catch {
            Log.entryError("Failed to upsert series: \(error)")
            return
        }
        if let index = self.series.firstIndex(where: { $0.id == series.id }) {
            self.series[index] = series
        } else {
            self.series.append(series)
        }
    }

    private func deleteSeriesRecord(_ id: String) {
        try? db.deleteSeries(id: id)
        series.removeAll { $0.id == id }
    }

    /// Drops the series record once it has no remaining occurrences.
    private func pruneIfEmpty(_ seriesId: String) {
        if occurrences(of: seriesId).isEmpty {
            deleteSeriesRecord(seriesId)
        }
    }
}
