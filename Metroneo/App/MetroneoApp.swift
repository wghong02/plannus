import SwiftUI

/// App entry point (DESIGNV2). Boots the Reminders-backed companion: a
/// `ReminderStore` (real EventKit, or an in-memory fake for previews / UI tests)
/// joined with a local performance sidecar, shared through the environment.
@main
struct MetroneoApp: App {
    @StateObject private var preferences = PerformancePreferencesService()
    @StateObject private var customization = PerformanceCustomizationService()
    @StateObject private var taskService: TaskService

    init() {
        // `-FAKE-REMINDERS` swaps in the in-memory fake (previews / UI tests) so the
        // companion runs without EventKit's permission prompt.
        let fakeReminders = CommandLine.arguments.contains("-FAKE-REMINDERS")
        let reminderStore: ReminderStore
        #if DEBUG
        reminderStore = fakeReminders ? FakeReminderStore.seeded() : EventKitReminderStore()
        #else
        reminderStore = EventKitReminderStore()
        #endif
        let sidecar = try! PerformanceSidecarStore(inMemory: fakeReminders)
        // UI tests get a volatile defaults suite (cleared each launch) so companion
        // settings — needs-rating window, list scope — don't leak across runs.
        let taskDefaults: UserDefaults
        if fakeReminders, let suite = UserDefaults(suiteName: "companion.fake") {
            suite.removePersistentDomain(forName: "companion.fake")
            taskDefaults = suite
        } else {
            taskDefaults = .standard
        }
        _taskService = StateObject(wrappedValue: TaskService(store: reminderStore, sidecar: sidecar, defaults: taskDefaults))
    }

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environmentObject(taskService)
                .environmentObject(preferences)
                .environmentObject(customization)
        }
    }
}
