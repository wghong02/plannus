import Foundation
import SwiftData

/// One completed occurrence of a recurring series (DESIGN R3.3), read from the
/// sidecar. Self-contained (carries a snapshot of the series) so it renders and
/// rates without the live series reminder.
public struct OccurrenceRecord: Equatable, Sendable {
    public let id: String            // composite "<seriesId>@<epoch>"
    public let seriesId: String
    public let title: String
    public let listId: String
    public let priority: ReminderPriority
    public let occurrenceDate: Date
    public let completionDate: Date
    public let metadata: PerformanceMetadata
}

/// Local SwiftData store for the performance **sidecar** (DESIGN R3): the
/// `{ rating, notes, estimated, actual }` Metroneo attaches to reminders, keyed by
/// external id, with per-entry writes and **defensive orphan reconciliation** (R3.2).
public final class PerformanceSidecarStore {
    private let container: ModelContainer
    private let context: ModelContext

    /// True when the store is mirrored to the user's private CloudKit database
    /// (DESIGN — Sync); false when running local-only (no capability / not signed in).
    public let isCloudBacked: Bool

    /// Ids seen absent from the live set on the *previous* successful sync — pruned
    /// only if still absent this sync (the R3.2 two-sync grace).
    private var pendingOrphans: Set<String> = []

    /// - Parameters:
    ///   - inMemory: true for previews/tests (isolated, no disk).
    ///   - cloudKitContainerID: the private CloudKit container to mirror into (DESIGN —
    ///     Sync). Ignored in memory or when iCloud isn't available.
    ///   - iCloudAvailable: whether the user is signed into iCloud (injectable for tests).
    ///   - storeURL: override the on-disk store location (injectable for tests).
    ///   - makeCloudContainer: builds the CloudKit-backed container (injectable so tests
    ///     can force a failure and assert the local fallback).
    ///
    /// **Graceful fallback:** if the CloudKit-backed container can't be built (iCloud
    /// unavailable, transient error, misconfiguration), it falls back to a plain local
    /// store so the app keeps working rather than failing to launch.
    public init(inMemory: Bool = false,
                cloudKitContainerID: String? = nil,
                iCloudAvailable: Bool = FileManager.default.ubiquityIdentityToken != nil,
                storeURL: URL? = nil,
                makeCloudContainer: ((String, URL) throws -> ModelContainer)? = nil) throws {
        if inMemory {
            container = try ModelContainer(for: StoredPerformance.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            isCloudBacked = false
            context = ModelContext(container)
            return
        }

        let url = storeURL ?? URL.applicationSupportDirectory.appending(path: "MetroneoSidecar.store")
        // Mirror to the user's private CloudKit database when iCloud is available; if
        // building that container throws for any reason, fall back to a local store so
        // connecting to the cloud can never crash the app.
        if let cloudKitContainerID, iCloudAvailable {
            let makeCloud = makeCloudContainer ?? { id, storeURL in
                try ModelContainer(for: StoredPerformance.self,
                                   configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .private(id)))
            }
            if let cloud = try? makeCloud(cloudKitContainerID, url) {
                container = cloud
                isCloudBacked = true
                context = ModelContext(container)
                return
            }
        }

        container = try ModelContainer(for: StoredPerformance.self, configurations: ModelConfiguration(url: url))
        isCloudBacked = false
        context = ModelContext(container)
    }

    /// The metadata for a reminder (or occurrence id), or `.empty` when none is stored.
    public func metadata(for id: String) -> PerformanceMetadata {
        guard let row = row(id) else { return .empty }
        return PerformanceMetadata(
            rating: row.rating, performanceNotes: row.performanceNotes,
            estimatedDuration: row.estimatedDuration, actualDuration: row.actualDuration
        )
    }

    /// Upserts one reminder's metadata; empty metadata **drops** a normal row (R3.1).
    /// Occurrence-snapshot rows are never dropped (they record a completed
    /// occurrence regardless of whether it's been rated yet, R3.3) — empty metadata
    /// just clears their performance fields.
    public func setMetadata(_ meta: PerformanceMetadata, for id: String) {
        let existing = row(id)
        if meta.isEmpty {
            if let existing, existing.isOccurrence {
                existing.rating = nil; existing.performanceNotes = nil
                existing.estimatedDuration = nil; existing.actualDuration = nil
            } else if let existing {
                context.delete(existing)
            }
        } else {
            let row = existing ?? insertNew(id)
            row.rating = meta.rating
            row.performanceNotes = meta.performanceNotes
            row.estimatedDuration = meta.estimatedDuration
            row.actualDuration = meta.actualDuration
        }
        try? context.save()
    }

    // MARK: - Occurrence snapshots (R3.3)

    /// The composite sidecar id for one occurrence of a recurring series.
    public static func occurrenceId(seriesId: String, occurrenceDate: Date) -> String {
        "\(seriesId)@\(Int(occurrenceDate.timeIntervalSince1970))"
    }

    /// Records a completed occurrence of a recurring series (DESIGN R3.3), keyed by
    /// its composite id. **Idempotent:** if the occurrence already exists (e.g. an
    /// exact in-app capture) it is left untouched, so a later best-effort detection
    /// can't clobber it or create a duplicate. Returns the occurrence id.
    @discardableResult
    public func recordOccurrence(
        seriesId: String, title: String, listId: String, priority: ReminderPriority,
        occurrenceDate: Date, completionDate: Date
    ) -> String {
        let id = Self.occurrenceId(seriesId: seriesId, occurrenceDate: occurrenceDate)
        if row(id) == nil {
            let row = insertNew(id)
            row.isOccurrence = true
            row.seriesId = seriesId
            row.seriesTitle = title
            row.seriesListId = listId
            row.seriesPriorityRaw = priority.rawValue
            row.occurrenceDate = occurrenceDate
            row.occurrenceCompletionDate = completionDate
            try? context.save()
        }
        return id
    }

    /// All recorded occurrence snapshots (R3.3).
    public func occurrences() -> [OccurrenceRecord] {
        rows().filter(\.isOccurrence).compactMap { row in
            guard let seriesId = row.seriesId,
                  let occurrenceDate = row.occurrenceDate,
                  let completionDate = row.occurrenceCompletionDate else { return nil }
            return OccurrenceRecord(
                id: row.reminderId, seriesId: seriesId,
                title: row.seriesTitle ?? "", listId: row.seriesListId ?? "",
                priority: ReminderPriority(rawValue: row.seriesPriorityRaw ?? 0) ?? .none,
                occurrenceDate: occurrenceDate, completionDate: completionDate,
                metadata: PerformanceMetadata(
                    rating: row.rating, performanceNotes: row.performanceNotes,
                    estimatedDuration: row.estimatedDuration, actualDuration: row.actualDuration
                )
            )
        }
    }

    // MARK: - Reconciliation (R3.2)

    /// Prunes sidecar rows whose reminder no longer exists — defensively (DESIGN R3.2):
    /// - `liveIds` must be the **full, unscoped** live id set (all lists); a scoped
    ///   subset would wrongly delete out-of-scope data.
    /// - **Empty-guard:** if the fetch failed or came back empty while the sidecar
    ///   holds data, nothing is pruned (an empty read is "unknown", not "all gone").
    /// - **Grace:** an id is dropped only after it's been absent across **two
    ///   consecutive** successful syncs.
    /// - Occurrence snapshots (R3.3) are historical and never pruned here.
    public func reconcile(liveIds: Set<String>, fetchSucceeded: Bool) {
        let normal = rows().filter { !$0.isOccurrence }
        // Empty-guard: don't treat a failed/empty read as "everything was deleted".
        guard fetchSucceeded, !(liveIds.isEmpty && !normal.isEmpty) else { return }

        let absentNow = Set(normal.map(\.reminderId)).subtracting(liveIds)
        var stillPending: Set<String> = []
        var changed = false
        for row in normal where absentNow.contains(row.reminderId) {
            if pendingOrphans.contains(row.reminderId) {
                context.delete(row); changed = true   // absent two syncs running → prune
            } else {
                stillPending.insert(row.reminderId)    // first absence → wait one more sync
            }
        }
        pendingOrphans = stillPending
        if changed { try? context.save() }
    }

    /// Deletes one row (normal or occurrence) outright — used by the "clear
    /// performance data" controls (DESIGN — Sync / Settings).
    public func clear(id: String) {
        if let row = row(id) { context.delete(row); try? context.save() }
    }

    /// Deletes every sidecar row.
    public func clearAll() {
        let all = rows()
        guard !all.isEmpty else { return }
        for row in all { context.delete(row) }
        try? context.save()
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

    private func insertNew(_ id: String) -> StoredPerformance {
        let new = StoredPerformance(reminderId: id)
        context.insert(new)
        return new
    }
}
