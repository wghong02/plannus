import Foundation
import Combine

/// The companion's read/write hub (DESIGN R2/R3/R6): fetches reminders from the
/// `ReminderStore`, joins the local performance sidecar, reconciles orphans, and
/// exposes the three lists the UI needs. Performance writes go to the sidecar;
/// reminder writes (R4) forward to the store (added when the editor lands).
public final class TaskService: ObservableObject {
    /// Incomplete reminders, joined (the Tasks list).
    @Published public private(set) var items: [TaskItem] = []
    /// Completed **and unrated** reminders within the look-back window (R6.1).
    @Published public private(set) var needsRating: [TaskItem] = []
    /// All rated reminders — the analytics population (R2.3), any completion date.
    @Published public private(set) var ratedItems: [TaskItem] = []
    /// The user's reminder lists (R5), for the Tasks grouping.
    @Published public private(set) var lists: [ReminderList] = []

    private let store: ReminderStore
    private let sidecar: PerformanceSidecarStore
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let window = "companion.needsRatingWindowDays"
        static let scope = "companion.listScope"
        static let recurringDue = "companion.recurringLastSeenDue"
    }

    /// Which lists to include (`nil` ⇒ all authorized lists). Default all; Settings
    /// narrows it (R5.3). Published so the Settings UI reflects changes; persist via
    /// ``setListScope(_:)``.
    @Published public var listScope: [String]?
    /// Needs-rating look-back window (R6.1a). Default 14 days. Persist via
    /// ``setNeedsRatingWindow(days:)``.
    @Published public var needsRatingWindow: TimeInterval = 14 * 86_400

    public init(store: ReminderStore, sidecar: PerformanceSidecarStore,
                listScope: [String]? = nil, defaults: UserDefaults = .standard) {
        self.store = store
        self.sidecar = sidecar
        self.defaults = defaults
        self.listScope = listScope
        // Load persisted companion settings (R5.3 / R6.1a).
        if let days = defaults.object(forKey: Keys.window) as? Double, days > 0 {
            needsRatingWindow = days * 86_400
        }
        // A stored scope (including an explicit empty "no lists" selection) wins over
        // the default; only an *unset* key (array == nil) leaves the default (all).
        if let ids = defaults.array(forKey: Keys.scope) as? [String] {
            self.listScope = ids
        }
    }

    /// The needs-rating window in whole days (R6.1a), for the Settings slider.
    public var needsRatingWindowDays: Int { Int((needsRatingWindow / 86_400).rounded()) }

    /// Persists + applies the needs-rating window, then refreshes (R6.1a).
    @MainActor
    public func setNeedsRatingWindow(days: Int) async {
        needsRatingWindow = Double(max(1, days)) * 86_400
        defaults.set(Double(max(1, days)), forKey: Keys.window)
        await refresh()
    }

    /// Persists + applies the list scope **synchronously**, then refreshes (R5.3).
    /// `nil` ⇒ all lists (the default); an explicit `[]` ⇒ **no** lists; otherwise
    /// exactly those lists. Empty is preserved, not coerced to "all" — otherwise
    /// turning off the last remaining list (or the only list) would snap every toggle
    /// back on ("can't toggle a list off"). The update is synchronous so a bound
    /// `Toggle` re-reading its `get` doesn't rubber-band to the old value.
    @MainActor
    public func setListScope(_ ids: [String]?) {
        listScope = ids
        if let ids { defaults.set(ids, forKey: Keys.scope) } else { defaults.removeObject(forKey: Keys.scope) }
        Task { await refresh() }
    }

    /// Subscribes to the store's external-change signal (`EKEventStoreChanged`, R1.3)
    /// and refreshes when reminders change in the Reminders app / Siri / another
    /// device. Call once at app start (not from unit tests, so refreshes stay
    /// deterministic there).
    public func observeExternalChanges() {
        guard cancellables.isEmpty else { return }
        store.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    /// Whether Reminders access is granted (R1.1).
    public var isAuthorized: Bool { store.isAuthorized }

    /// Requests Reminders access and, if granted, loads (R1.1).
    @MainActor
    public func requestAccess() async -> Bool {
        let granted = await store.requestAccess()
        if granted { await refresh() }
        return granted
    }

    /// Re-fetches reminders, reconciles the sidecar defensively against the **full,
    /// unscoped** live set (R3.2), captures best-effort recurring occurrences (R3.3),
    /// then filters to the Settings list scope (R5.3) to rebuild
    /// `items` / `needsRating` / `ratedItems` (R2/R3).
    @MainActor
    public func refresh(now: Date = Date()) async {
        lists = store.lists()
        // Fetch the FULL set (all lists) — reconciliation must never see a scoped
        // subset, or it would prune out-of-scope performance data (R3.2). Scope is
        // applied in memory below for display only.
        let incomplete = await store.incompleteReminders(inLists: nil)
        // All completed (not just the window) so reconciliation and the rated
        // population see every existing reminder.
        let completed = await store.completedReminders(since: .distantPast, inLists: nil)

        // Best-effort external recurrence capture: a recurring series whose due date
        // advanced since we last saw it had an occurrence completed elsewhere (R3.3).
        captureAdvancedRecurrences(incomplete, now: now)

        let liveIds = Set(incomplete.map(\.id)).union(completed.map(\.id))
        // `isAuthorized == false` ⇒ EventKit returns [] for reasons other than
        // deletion; don't let that prune the sidecar (R3.2 empty-guard).
        sidecar.reconcile(liveIds: liveIds, fetchSucceeded: store.isAuthorized)

        let occurrences = sidecar.occurrences()
            .filter { inScope($0.listId) }
            .map(TaskItem.init(occurrence:))

        items = incomplete.filter { inScope($0.listId) }.map(join)

        let windowStart = now.addingTimeInterval(-needsRatingWindow)
        func recentUnrated(_ completionDate: Date?, _ rating: Int?) -> Bool {
            (completionDate ?? .distantPast) >= windowStart && rating == nil
        }
        let completedNeeds = completed
            .filter { inScope($0.listId) && recentUnrated($0.completionDate, sidecar.metadata(for: $0.id).rating) }
            .map(join)
        let occurrenceNeeds = occurrences.filter { recentUnrated($0.completionDate, $0.rating) }
        needsRating = (completedNeeds + occurrenceNeeds)
            .sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }

        let ratedReminders = (incomplete + completed).filter { inScope($0.listId) }.map(join).filter(\.isRated)
        ratedItems = ratedReminders + occurrences.filter(\.isRated)
    }

    /// Whether a list is in the current display scope (`nil` ⇒ all lists, R5.3).
    private func inScope(_ listId: String) -> Bool { listScope.map { $0.contains(listId) } ?? true }

    /// Detects recurring series whose due date advanced since the last sync and
    /// records one occurrence snapshot for the prior occurrence — the best-effort
    /// external-completion path (R3.3). Idempotent with the exact in-app capture.
    private func captureAdvancedRecurrences(_ incomplete: [ReminderData], now: Date) {
        var seen = defaults.dictionary(forKey: Keys.recurringDue) as? [String: Double] ?? [:]
        for r in incomplete where r.isRecurring {
            guard let due = r.dueDate else { continue }
            let epoch = due.timeIntervalSince1970
            if let prev = seen[r.id], epoch > prev {
                sidecar.recordOccurrence(
                    seriesId: r.id, title: r.title, listId: r.listId, priority: r.priority,
                    occurrenceDate: Date(timeIntervalSince1970: prev), completionDate: now
                )
            }
            seen[r.id] = epoch
        }
        defaults.set(seen, forKey: Keys.recurringDue)
    }

    /// All completed reminders (and recurring occurrences) in the current scope,
    /// newest first — the **Browse Completed** surface (R6.5) for rating anything on
    /// demand, including completions older than the Needs-rating window (R6.1a).
    @MainActor
    public func browseCompleted() async -> [TaskItem] {
        let completed = await store.completedReminders(since: .distantPast, inLists: nil)
        let normal = completed.filter { inScope($0.listId) }.map(join)
        let occ = sidecar.occurrences().filter { inScope($0.listId) }.map(TaskItem.init(occurrence:))
        return (normal + occ).sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    // MARK: - Reminder writes (R4 — forward to Apple Reminders, then refresh)

    /// Creates or updates a reminder (R4.1/R4.2): a blank `id` creates one in
    /// `listId` (else the default list); returns the saved snapshot.
    @discardableResult @MainActor
    public func save(_ reminder: ReminderData) async -> ReminderData? {
        let saved = store.save(reminder)
        await refresh()
        return saved
    }

    /// Marks a reminder complete/incomplete (R4.3). Completing a **recurring**
    /// reminder in-app captures an exact occurrence snapshot (R3.3) *before* Apple
    /// advances the series, so that occurrence can be rated on its own.
    @MainActor
    public func setCompleted(id: String, _ completed: Bool, now: Date = Date()) async {
        if completed, let item = items.first(where: { $0.id == id }), item.isRecurring {
            sidecar.recordOccurrence(
                seriesId: id, title: item.title, listId: item.listId, priority: item.priority,
                occurrenceDate: item.dueDate ?? now, completionDate: now
            )
        }
        store.setCompleted(id: id, completed)
        await refresh(now: now)
    }

    /// Deletes a reminder and drops its sidecar performance data (R4.1 / R3.2).
    @MainActor
    public func delete(id: String) async {
        store.delete(id: id)
        sidecar.setMetadata(.empty, for: id)
        await refresh()
    }

    /// Creates a new Reminders list (R5.2).
    @discardableResult
    public func createList(named name: String) -> ReminderList? {
        store.createList(named: name)
    }

    // MARK: - Performance writes (R6 — sidecar, then refresh)

    @MainActor
    public func rate(id: String, rating: Int?, notes: String? = nil) async {
        writeMetadata(for: id) { $0.rating = rating; $0.performanceNotes = notes }
        await refresh()
    }

    /// Records a rating, notes, and actual time together — the rating sheet's Save
    /// (R6.2) — in one sidecar write + refresh.
    @MainActor
    public func recordRating(id: String, rating: Int?, notes: String?, actualMinutes: Int?) async {
        writeMetadata(for: id) {
            $0.rating = rating
            $0.performanceNotes = notes
            $0.actualDuration = actualMinutes
        }
        await refresh()
    }

    @MainActor
    public func setEstimatedDuration(id: String, minutes: Int?) async {
        writeMetadata(for: id) { $0.estimatedDuration = minutes }
        await refresh()
    }

    @MainActor
    public func setActualDuration(id: String, minutes: Int?) async {
        writeMetadata(for: id) { $0.actualDuration = minutes }
        await refresh()
    }

    private func writeMetadata(for id: String, _ change: (inout PerformanceMetadata) -> Void) {
        var m = sidecar.metadata(for: id)
        change(&m)
        sidecar.setMetadata(m, for: id)
    }

    private func join(_ r: ReminderData) -> TaskItem {
        TaskItem(reminder: r, metadata: sidecar.metadata(for: r.id))
    }
}
