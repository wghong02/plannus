import Foundation
import SwiftData

/// Local SwiftData store for the performance **sidecar** (DESIGN R3): the
/// `{ rating, notes, estimated, actual }` Metroneo attaches to reminders, keyed by
/// external id, with per-entry writes and **orphan reconciliation** (R3.2).
public final class PerformanceSidecarStore {
    private let container: ModelContainer
    private let context: ModelContext

    /// - Parameter inMemory: true for previews/tests (isolated, no disk).
    public init(inMemory: Bool = false) throws {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let url = URL.applicationSupportDirectory.appending(path: "MetroneoSidecar.store")
            config = ModelConfiguration(url: url)
        }
        container = try ModelContainer(for: StoredPerformance.self, configurations: config)
        context = ModelContext(container)
    }

    /// The metadata for a reminder, or `.empty` when none is stored.
    public func metadata(for id: String) -> PerformanceMetadata {
        guard let row = row(id) else { return .empty }
        return PerformanceMetadata(
            rating: row.rating, performanceNotes: row.performanceNotes,
            estimatedDuration: row.estimatedDuration, actualDuration: row.actualDuration
        )
    }

    /// Upserts one reminder's metadata; empty metadata **drops** the row (R3.1).
    public func setMetadata(_ meta: PerformanceMetadata, for id: String) {
        if meta.isEmpty {
            if let row = row(id) { context.delete(row) }
        } else {
            let row = try? existingOrNew(id)
            row?.rating = meta.rating
            row?.performanceNotes = meta.performanceNotes
            row?.estimatedDuration = meta.estimatedDuration
            row?.actualDuration = meta.actualDuration
        }
        try? context.save()
    }

    /// Prunes sidecar rows whose reminder is no longer present — a reminder deleted
    /// in Apple's app takes its performance data with it (R3.2). `liveIds` must be
    /// the **full** set of existing reminder ids (incomplete + all completed), not a
    /// windowed subset, so old-but-alive reminders aren't wrongly pruned.
    public func reconcile(liveIds: Set<String>) {
        var changed = false
        for row in rows() where !liveIds.contains(row.reminderId) {
            context.delete(row)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// All stored ids (diagnostics/tests).
    public func storedIds() -> Set<String> { Set(rows().map(\.reminderId)) }

    // MARK: - Helpers

    private func rows() -> [StoredPerformance] {
        (try? context.fetch(FetchDescriptor<StoredPerformance>())) ?? []
    }

    private func row(_ id: String) -> StoredPerformance? {
        var d = FetchDescriptor<StoredPerformance>(predicate: #Predicate { $0.reminderId == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    private func existingOrNew(_ id: String) throws -> StoredPerformance {
        if let row = row(id) { return row }
        let new = StoredPerformance(reminderId: id)
        context.insert(new)
        return new
    }
}
