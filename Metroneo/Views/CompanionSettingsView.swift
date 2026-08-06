import SwiftUI

/// Settings tab for the companion (DESIGNV2). Companion-specific controls —
/// **priority weights** (R7.3), **Reminders list scope** (R5.3), and the
/// **needs-rating window** (R6.1a) — plus the carried-over Performance
/// customization screen (D8/D10/D12) and About.
struct CompanionSettingsView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var custom: PerformanceCustomizationService

    @State private var windowDays = 14

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version).\(build)"
    }

    var body: some View {
        List {
            Section("Priority Weights") {
                Text("How much each Apple Reminders priority counts toward your weighted average.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ReminderPriority.allCases, id: \.self) { priority in
                    Stepper("\(priority.label): \(weight(priority))",
                            value: weightBinding(priority), in: 0...10)
                        .accessibilityIdentifier("weight-\(priority.label)")
                }
            }

            Section("Needs-rating window") {
                Stepper("Look back \(windowDays) day\(windowDays == 1 ? "" : "s")",
                        value: $windowDays, in: 1...60)
                    .accessibilityIdentifier("needsRatingWindowStepper")
                    .onChange(of: windowDays) { _, days in
                        Task { await taskService.setNeedsRatingWindow(days: days) }
                    }
                Text("Completed reminders wait this long for a rating before dropping out of the inbox.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reminder lists") {
                Text("Which lists Metroneo reads. All are included by default.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(taskService.lists) { list in
                    Toggle(list.title, isOn: scopeBinding(list.id))
                        .accessibilityIdentifier("listScope-\(list.title)")
                }
            }

            Section("Personal Preferences") {
                NavigationLink("Performance") { PerformanceCustomizationScreen() }
                    .accessibilityIdentifier("performanceSettingsLink")
            }

            Section("About") {
                HStack { Text("Version"); Spacer(); Text(Self.appVersion).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
        .onAppear { windowDays = taskService.needsRatingWindowDays }
    }

    // MARK: - Priority weights

    private func weight(_ p: ReminderPriority) -> Int { custom.priorityWeights.weight(for: p) }

    private func weightBinding(_ p: ReminderPriority) -> Binding<Int> {
        Binding(
            get: { weight(p) },
            set: { newValue in
                var w = custom.priorityWeights
                switch p {
                case .none: w.none = newValue
                case .low: w.low = newValue
                case .medium: w.medium = newValue
                case .high: w.high = newValue
                }
                custom.setPriorityWeights(w)
            }
        )
    }

    // MARK: - List scope

    /// A list is "on" when scope is nil (all) or includes it. Turning one off
    /// narrows the scope to the remaining lists; turning the last one back on
    /// clears the scope to "all".
    private func scopeBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { taskService.listScope.map { $0.contains(id) } ?? true },
            set: { on in
                let all = taskService.lists.map(\.id)
                var current = Set(taskService.listScope ?? all)
                if on { current.insert(id) } else { current.remove(id) }
                let next = all.filter { current.contains($0) }
                Task { await taskService.setListScope(next.count == all.count ? nil : next) }
            }
        )
    }
}
