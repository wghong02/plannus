import SwiftUI

/// App entry point (DESIGN.md §10, v2). Boots the v2 entry store, runs the
/// one-time migration from the legacy task/event store, and shares the services
/// through the environment.
@main
struct MetroneoApp: App {
    @StateObject private var entryService: EntryService
    @StateObject private var collectionService: CollectionService
    @StateObject private var seriesService: SeriesService
    @StateObject private var preferences = PerformancePreferencesService()
    @StateObject private var customization = PerformanceCustomizationService()

    private let database: EntryDatabase

    init() {
        // A failure to open the on-disk store is fatal — no silent fallback (§10).
        let db = try! EntryDatabase()
        self.database = db
        let entries = EntryService(db: db)
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
                .onAppear {
                    entryService.loadEntries()
                    collectionService.loadCollections()
                    seriesService.loadSeries()
                }
        }
    }
}
