import SwiftUI

/// Gates the companion UI on Reminders access (DESIGN R1.1): shows a grant
/// prompt until access is granted, then the wrapped content.
struct ReminderAccessGate<Content: View>: View {
    @EnvironmentObject private var taskService: TaskService
    @ViewBuilder let content: () -> Content
    @State private var authorized = false

    var body: some View {
        Group {
            if authorized {
                content()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "checklist").font(.system(size: 48)).foregroundStyle(.blue)
                    Text("Metroneo works with your Reminders")
                        .font(.headline).multilineTextAlignment(.center)
                    Text("Grant access to see your reminders and track how you're doing over time.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Grant Access") {
                        Task { authorized = await taskService.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("grantAccessButton")
                }
                .padding()
            }
        }
        .task { authorized = taskService.isAuthorized }
    }
}
