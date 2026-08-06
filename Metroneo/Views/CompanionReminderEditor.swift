import SwiftUI

/// The single editor for a companion reminder (DESIGN R4/R7). Writes the reminder
/// half (title/notes/due/priority/list/early-reminder alarm) back to Apple Reminders
/// through `TaskService`, and the estimated duration to the local sidecar. Recurrence
/// is read-only (R-recurrence): a repeating reminder shows a note but is edited in
/// Apple Reminders.
struct CompanionReminderEditor: View {
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    /// The item being edited, or `nil` for a new reminder.
    private let existing: TaskItem?

    @State private var title: String
    @State private var notes: String
    @State private var priority: ReminderPriority
    @State private var listId: String

    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var hasDueTime: Bool

    @State private var hasAlarm: Bool
    @State private var alarmMinutes: Int
    @State private var customLead: Bool

    @State private var estimatedText: String

    init(item: TaskItem? = nil) {
        self.existing = item
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _priority = State(initialValue: item?.priority ?? .none)
        _listId = State(initialValue: item?.listId ?? "")
        _hasDue = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? DateTimeUtilities.endOfDay(Date()))
        _hasDueTime = State(initialValue: item?.hasDueTime ?? false)
        let firstAlarm = item?.alarmOffsetMinutes.first
        _hasAlarm = State(initialValue: firstAlarm != nil)
        _alarmMinutes = State(initialValue: firstAlarm ?? 15)
        _customLead = State(initialValue: firstAlarm.map { !ReminderLead.isPreset($0) } ?? false)
        _estimatedText = State(initialValue: item?.estimatedDuration.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New Reminder", text: $title)
                        .accessibilityIdentifier("reminderTitleField")
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("List") {
                    Picker("List", selection: $listId) {
                        ForEach(taskService.lists) { list in Text(list.title).tag(list.id) }
                    }
                    .accessibilityIdentifier("listPicker")
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(ReminderPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("priorityPicker")
                }

                dueSection
                if hasDue { alarmSection }

                Section("Estimated duration (minutes)") {
                    TextField("Estimated", text: $estimatedText).keyboardType(.numberPad)
                        .accessibilityIdentifier("estimatedField")
                }

                if existing?.isRecurring == true {
                    Section {
                        Label("Repeats — edit the recurrence in Apple Reminders.", systemImage: "repeat")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete Reminder", role: .destructive) { delete() }
                            .accessibilityIdentifier("deleteReminderButton")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                        .accessibilityIdentifier("saveReminderButton")
                }
            }
            .onAppear {
                // Default a new reminder into the user's default list.
                if listId.isEmpty { listId = taskService.lists.first(where: \.isDefault)?.id ?? taskService.lists.first?.id ?? "" }
            }
        }
    }

    private var dueSection: some View {
        Section("Due") {
            Toggle("Due date", isOn: $hasDue).accessibilityIdentifier("dueToggle")
            if hasDue {
                DatePicker("Due", selection: $dueDate,
                           displayedComponents: hasDueTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Set due time", isOn: $hasDueTime).accessibilityIdentifier("dueTimeToggle")
            }
        }
    }

    private var alarmSection: some View {
        Section("Early reminder") {
            Toggle("Remind me before", isOn: $hasAlarm).accessibilityIdentifier("alarmToggle")
            if hasAlarm {
                Toggle("Custom early reminder", isOn: $customLead).accessibilityIdentifier("customLeadToggle")
                if customLead {
                    HStack {
                        Text("Minutes before")
                        Spacer()
                        TextField("", value: $alarmMinutes, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                            .accessibilityIdentifier("customLeadField")
                    }
                    Text(ReminderLead.label(minutes: max(0, alarmMinutes)))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Early reminder", selection: $alarmMinutes) {
                        ForEach(ReminderLead.presets, id: \.self) { Text(ReminderLead.label(minutes: $0)).tag($0) }
                    }
                }
            }
        }
    }

    // MARK: - Save / delete

    private func save() {
        var reminder = existing?.reminderData ?? ReminderData(title: "")
        reminder.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? "New Reminder" : title
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.priority = priority
        reminder.listId = listId
        reminder.dueDate = hasDue ? dueDate : nil
        reminder.hasDueTime = hasDue && hasDueTime
        reminder.alarmOffsetMinutes = (hasDue && hasAlarm) ? [max(0, alarmMinutes)] : []

        let estimated = Int(estimatedText)
        Task {
            let saved = await taskService.save(reminder)
            if let id = saved?.id, !id.isEmpty {
                await taskService.setEstimatedDuration(id: id, minutes: estimated)
            }
            dismiss()
        }
    }

    private func delete() {
        guard let id = existing?.id else { return }
        Task { await taskService.delete(id: id); dismiss() }
    }
}
