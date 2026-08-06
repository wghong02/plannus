import Foundation
import Combine

/// The companion's read/write hub (DESIGNV2 R2/R3/R6): fetches reminders from the
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

    private enum Keys {
        static let window = "companion.needsRatingWindowDays"
        static let scope = "companion.listScope"
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
        if let ids = defaults.array(forKey: Keys.scope) as? [String], !ids.isEmpty {
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

    /// Persists + applies the list scope (`nil`/empty ⇒ all lists), then refreshes (R5.3).
    @MainActor
    public func setListScope(_ ids: [String]?) async {
        let scope = (ids?.isEmpty ?? true) ? nil : ids
        listScope = scope
        if let scope { defaults.set(scope, forKey: Keys.scope) } else { defaults.removeObject(forKey: Keys.scope) }
        await refresh()
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

    /// Re-fetches reminders, reconciles the sidecar against the **full** live set,
    /// and rebuilds `items` / `needsRating` / `ratedItems` (R2/R3).
    @MainActor
    public func refresh(now: Date = Date()) async {
        lists = store.lists()
        let incomplete = await store.incompleteReminders(inLists: listScope)
        // All completed (not just the window) so reconciliation and the rated
        // population see every existing reminder.
        let completed = await store.completedReminders(since: .distantPast, inLists: listScope)

        let liveIds = Set(incomplete.map(\.id)).union(completed.map(\.id))
        sidecar.reconcile(liveIds: liveIds)

        items = incomplete.map(join)

        let windowStart = now.addingTimeInterval(-needsRatingWindow)
        needsRating = completed
            .filter { ($0.completionDate ?? .distantPast) >= windowStart && sidecar.metadata(for: $0.id).rating == nil }
            .map(join)

        ratedItems = (incomplete + completed).map(join).filter(\.isRated)
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

    /// Marks a reminder complete/incomplete (R4.3).
    @MainActor
    public func setCompleted(id: String, _ completed: Bool) async {
        store.setCompleted(id: id, completed)
        await refresh()
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
