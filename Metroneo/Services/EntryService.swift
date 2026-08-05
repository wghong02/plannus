import Foundation
import Combine

/// Notified when an entry is deleted so **derived caches stay coherent** without
/// a reload (D1.5). `EntryDatabase.deleteEntry` drops the id from every
/// collection in the *store* (D5.6); the observer mirrors that in the in-memory
/// caches that hold the same membership (e.g. ``CollectionService``).
public protocol EntryDeletionObserver: AnyObject {
    func entryDeleted(id: String)
}

/// Observable entry cache backed by an ``EntryDatabase`` (DESIGN.md D1/D6).
///
/// Every mutation is a **single-entity write** (D1): it updates the in-memory
/// `@Published` copy **in place** *and* persists just that one entity, so the UI
/// reflects the change immediately (D1.5). Ids are assigned at construction (D2)
/// and never change. Complete/rate are gated by the entry's aspects (D6.3) — a
/// call on an off aspect, or on a missing id, is a defensive **no-op**.
public final class EntryService: ObservableObject {
    @Published public private(set) var entries: [Entry] = []

    private let db: EntryDatabase
    /// Optional reminder side-effect hook (D9). `nil` in unit tests.
    private let scheduler: ReminderScheduling?
    /// Keeps membership-holding caches coherent on delete (D1.5 / D5.6). Weak so
    /// the observer (a peer service) isn't retained. Wired at bootstrap (§10).
    public weak var deletionObserver: EntryDeletionObserver?

    public init(db: EntryDatabase, scheduler: ReminderScheduling? = nil) {
        self.db = db
        self.scheduler = scheduler
    }

    // MARK: - Loading

    @discardableResult
    public func loadEntries() -> [Entry] {
        entries = (try? db.loadEntries()) ?? []
        refreshReminderBadge()
        return entries
    }

    /// Sets the app-icon badge to the current due-reminder count (D18). Called
    /// after every mutation and on load; also safe to call when the app returns to
    /// the foreground so the "due" total is current.
    public func refreshReminderBadge() {
        scheduler?.setBadgeCount(ReminderTiming.dueReminderCount(entries))
    }

    // MARK: - Mutations (each persists one entity immediately)

    /// Inserts or updates one entry by id (D1.1). Other entries are untouched.
    public func upsertEntry(_ entry: Entry) {
        do {
            try db.upsertEntry(entry)
        } catch {
            Log.entryError("Failed to upsert entry: \(error)")
            return
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        scheduler?.reschedule(for: entry, allEntries: entries)
        refreshReminderBadge()
    }

    /// Removes one entry (D1.2) and drops its id from every collection (D5.6).
    /// Unknown id is a no-op.
    public func deleteEntry(id: String) {
        do {
            try db.deleteEntry(id: id)
        } catch {
            Log.entryError("Failed to delete entry: \(error)")
            return
        }
        entries.removeAll { $0.id == id }
        scheduler?.cancel(entryId: id)
        refreshReminderBadge()
        // The store dropped this id from every collection (D5.6); mirror that in
        // the collection cache so no stale/dangling member id survives.
        deletionObserver?.entryDeleted(id: id)
    }

    /// Marks an entry complete (`completedAt = now`). No-op if the entry isn't
    /// completable or the id is unknown (D6.3 gating).
    public func completeEntry(id: String, at date: Date = Date()) {
        guard let entry = entries.first(where: { $0.id == id }), entry.isCompletable else { return }
        mutate(id) { $0.completion?.completedAt = date }
    }

    /// Clears completion. No-op if not completable / unknown id.
    public func uncompleteEntry(id: String) {
        guard let entry = entries.first(where: { $0.id == id }), entry.isCompletable else { return }
        mutate(id) { $0.completion?.completedAt = nil }
    }

    /// Records a performance rating (+ optional notes). No-op if not ratable /
    /// unknown id (D6.3 gating). Passing `notes: nil` clears the notes.
    public func rateEntry(id: String, performance: Int, notes: String? = nil) {
        guard let entry = entries.first(where: { $0.id == id }), entry.isRatable else { return }
        mutate(id) {
            $0.rating?.performanceRating = performance
            $0.rating?.performanceNotes = notes
        }
    }

    /// Sets the actual duration (completion sheet / editor, D14). No-op on unknown id.
    public func setActualDuration(id: String, minutes: Int?) {
        mutate(id) { $0.actualDuration = minutes }
    }

    // MARK: - Helpers

    /// Applies an in-place change to the entry with `id`, persists that one
    /// entity, and updates the observable copy. Missing id → no-op (ESVC-05).
    private func mutate(_ id: String, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries[index]
        change(&updated)
        do {
            try db.upsertEntry(updated)
        } catch {
            Log.entryError("Failed to persist entry mutation: \(error)")
            return
        }
        entries[index] = updated
        // Completing cancels, un-completing re-arms, a time change reschedules (D9.5).
        scheduler?.reschedule(for: updated, allEntries: entries)
        refreshReminderBadge()
    }
}
