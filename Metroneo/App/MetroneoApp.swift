import SwiftUI

/// App entry point (DESIGN.md §10, v2). Boots the v2 entry store, wires reminder
/// notifications, and shares the services through the environment.
@main
struct MetroneoApp: App {
    @StateObject private var entryService: EntryService
    @StateObject private var collectionService: CollectionService
    @StateObject private var seriesService: SeriesService
    @StateObject private var preferences = PerformancePreferencesService()
    @StateObject private var customization = PerformanceCustomizationService()
    @StateObject private var reminderScheduler: ReminderScheduler
    @StateObject private var router: NotificationRouter

    private let database: EntryDatabase

    init() {
        // A failure to open the on-disk store is fatal — no silent fallback (§10).
        let db = try! EntryDatabase()
        self.database = db

        // UI tests launch with a clean store for deterministic flows.
        if CommandLine.arguments.contains("-UITEST-RESET") { try? db.reset() }

        #if DEBUG
        // Test-support seed: rated entries across recent weeks so the Performance
        // charts (D16) have data to render (used by MetroneoUITests).
        if CommandLine.arguments.contains("-SEED-PERF") {
            try? db.reset()
            let cal = Calendar.current
            let data: [(Int, Int)] = [(1, 88), (2, 95), (3, 72), (8, 64), (9, 60), (10, 91), (15, 55), (18, 78), (24, 83), (30, 45)]
            for (daysAgo, rating) in data {
                let date = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
                try? db.upsertEntry(Entry(title: "Session \(daysAgo)d ago",
                                          completion: Completion(completedAt: date),
                                          rating: Rating(performanceRating: rating)))
            }
        }
        #endif

        let router = NotificationRouter()
        let scheduler = ReminderScheduler(router: router)
        _router = StateObject(wrappedValue: router)
        _reminderScheduler = StateObject(wrappedValue: scheduler)

        let entries = EntryService(db: db, scheduler: scheduler)
        _entryService = StateObject(wrappedValue: entries)
        _collectionService = StateObject(wrappedValue: CollectionService(db: db))
        _seriesService = StateObject(wrappedValue: SeriesService(db: db, entries: entries))
    }

    var body: some Scene {
        WindowGroup {
            RootView(database: database)
                .environmentObject(entryService)
                .environmentObject(collectionService)
                .environmentObject(seriesService)
                .environmentObject(preferences)
                .environmentObject(customization)
                .environmentObject(reminderScheduler)
                .environmentObject(router)
                .onAppear {
                    entryService.loadEntries()
                    collectionService.loadCollections()
                    seriesService.loadSeries()
                }
        }
    }
}
