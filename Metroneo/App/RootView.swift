import SwiftUI

/// Bottom tab bar with the app's four destinations (DESIGN.md §1, v2). Tab
/// selection is driven by ``NotificationRouter`` so a tapped reminder can jump to
/// the Calendar (D9.4). The first-run walkthrough (D13) covers the app once.
struct RootView: View {
    let database: EntryDatabase

    @EnvironmentObject private var router: NotificationRouter
    @EnvironmentObject private var entryService: EntryService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(onboardingSeenKey) private var onboardingSeen = false
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }.tag(0)
            TaskListView()
                .tabItem { Label("Tasks", systemImage: "list.bullet") }.tag(1)
            PerformanceView()
                .tabItem { Label("Performance", systemImage: "chart.bar") }.tag(2)
            SettingsView(database: database)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(.blue)
        // Bind the cover to real @State so dismissal is reliable; persist the flag.
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                OnboardingGate.markSeen()
                onboardingSeen = true
                showOnboarding = false
            }
        }
        .onAppear { showOnboarding = OnboardingGate.shouldShow() }
        .onChange(of: onboardingSeen) { _, seen in showOnboarding = !seen }
        // Recompute the due-reminder badge whenever the app returns to the fore (D18).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { entryService.refreshReminderBadge() }
        }
    }
}
