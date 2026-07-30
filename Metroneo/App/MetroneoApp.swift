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
