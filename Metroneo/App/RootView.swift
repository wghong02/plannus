import SwiftUI

/// Bottom tab bar with the app's four destinations (DESIGN.md §1, v2). The Tasks
/// tab hosts both entries and collections via its internal All ⇄ By-collection
/// toggle (D6.7).
struct RootView: View {
    let database: EntryDatabase

    var body: some View {
        TabView {
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            TaskListView()
                .tabItem { Label("Tasks", systemImage: "list.bullet") }

            PerformanceView()
                .tabItem { Label("Performance", systemImage: "chart.bar") }

            SettingsView(database: database)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.blue)
    }
}
