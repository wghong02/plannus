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

    private let store: ReminderStore
    private let sidecar: PerformanceSidecarStore

    /// Which lists to include (`nil` ⇒ all authorized lists). Default all; Settings
    /// narrows it (R5.3).
    public var listScope: [String]?
    /// Needs-rating look-back window (R6.1a). Default 14 days.
    public var needsRatingWindow: TimeInterval = 14 * 86_400

    public init(store: ReminderStore, sidecar: PerformanceSidecarStore, listScope: [String]? = nil) {
        self.store = store
        self.sidecar = sidecar
        self.listScope = listScope
    }

    /// Re-fetches reminders, reconciles the sidecar against the **full** live set,
    /// and rebuilds `items` / `needsRating` / `ratedItems` (R2/R3).
    @MainActor
    public func refresh(now: Date = Date()) async {
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

    // MARK: - Performance writes (sidecar; caller refreshes to re-join)

    public func rate(id: String, rating: Int?, notes: String? = nil) {
        var m = sidecar.metadata(for: id)
        m.rating = rating
        m.performanceNotes = notes
        sidecar.setMetadata(m, for: id)
    }

    public func setEstimatedDuration(id: String, minutes: Int?) {
        var m = sidecar.metadata(for: id)
        m.estimatedDuration = minutes
        sidecar.setMetadata(m, for: id)
    }

    public func setActualDuration(id: String, minutes: Int?) {
        var m = sidecar.metadata(for: id)
        m.actualDuration = minutes
        sidecar.setMetadata(m, for: id)
    }

    private func join(_ r: ReminderData) -> TaskItem {
        TaskItem(reminder: r, metadata: sidecar.metadata(for: r.id))
    }
}
