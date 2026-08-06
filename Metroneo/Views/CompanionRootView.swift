import SwiftUI

/// Root of the app (DESIGN): a Tasks tab (reminders + Needs-rating inbox), a
/// Performance tab, and Settings. Tasks and Performance are gated on Reminders
/// access; a first-run walkthrough (D13) is shown once via ``OnboardingGate``.
struct CompanionRootView: View {
    /// Store backing the onboarding "seen" flag — `.standard` in the app, a
    /// volatile suite under `-FAKE-REMINDERS` so UI tests stay deterministic.
    private let defaults: UserDefaults
    @State private var showOnboarding: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _showOnboarding = State(initialValue: OnboardingGate.shouldShow(defaults))
    }

    var body: some View {
        TabView {
            NavigationStack {
                ReminderAccessGate { CompanionTasksView() }
                    .navigationTitle("Tasks")
            }
            .tabItem { Label("Tasks", systemImage: "checklist") }

            NavigationStack {
                ReminderAccessGate { CompanionPerformanceView() }
            }
            .tabItem { Label("Performance", systemImage: "chart.line.uptrend.xyaxis") }

            NavigationStack {
                CompanionSettingsView(defaults: defaults)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                OnboardingGate.markSeen(defaults)
                showOnboarding = false
            }
        }
    }
}
