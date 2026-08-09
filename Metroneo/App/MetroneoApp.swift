import SwiftUI

/// App entry point (DESIGN). Boots the Reminders-backed companion: a
/// `ReminderStore` (real EventKit, or an in-memory fake for previews / UI tests)
/// joined with a local performance sidecar, shared through the environment.
@main
struct MetroneoApp: App {
    @StateObject private var preferences = PerformancePreferencesService()
    @StateObject private var customization = PerformanceCustomizationService()
    @StateObject private var taskService: TaskService

    /// Store backing companion settings + the onboarding flag; a volatile suite
    /// under `-FAKE-REMINDERS` so UI-test state never leaks across launches.
    private let launchDefaults: UserDefaults

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
        // Mirror the sidecar to the user's private iCloud database (DESIGN — Sync);
        // stays local under UI tests, when the user isn't signed into iCloud, or if the
        // CloudKit container can't be built (graceful fallback — never crashes).
        let sidecar = try! PerformanceSidecarStore(
            inMemory: fakeReminders,
            cloudKitContainerID: fakeReminders ? nil : "iCloud.com.gladiolus.Metroneo")
        // UI tests get a volatile defaults suite (cleared each launch) so companion
        // settings — needs-rating window, list scope — don't leak across runs.
        let taskDefaults: UserDefaults
        if fakeReminders, let suite = UserDefaults(suiteName: "companion.fake") {
            suite.removePersistentDomain(forName: "companion.fake")
            taskDefaults = suite
        } else {
            taskDefaults = .standard
        }
        // UI tests skip the first-run walkthrough by default (deterministic);
        // `-SHOW-ONBOARDING` forces it for the onboarding test.
        if fakeReminders, !CommandLine.arguments.contains("-SHOW-ONBOARDING") {
            OnboardingGate.markSeen(taskDefaults)
        }
        self.launchDefaults = taskDefaults
        // Publish widget snapshots on refresh in the real app (not under UI tests).
        let widgetPublisher: WidgetSnapshotPublishing? = fakeReminders ? nil : AppWidgetPublisher()
        let service = TaskService(store: reminderStore, sidecar: sidecar,
                                  defaults: taskDefaults, widgetPublisher: widgetPublisher,
                                  syncConfigured: !fakeReminders)
        service.observeExternalChanges() // refresh on EKEventStoreChanged (R1.3)
        _taskService = StateObject(wrappedValue: service)
    }

    var body: some Scene {
        WindowGroup {
            CompanionRootView(defaults: launchDefaults)
                .environmentObject(taskService)
                .environmentObject(preferences)
                .environmentObject(customization)
        }
    }
}
