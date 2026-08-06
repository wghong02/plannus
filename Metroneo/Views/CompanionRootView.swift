import SwiftUI

/// Root of the companion app (DESIGNV2). A Tasks tab (reminders + Needs-rating
/// inbox) and a Performance tab, both gated on Reminders access. Settings moves
/// over next; the old `Entry` root is retired in the final phase.
struct CompanionRootView: View {
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
                CompanionSettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
