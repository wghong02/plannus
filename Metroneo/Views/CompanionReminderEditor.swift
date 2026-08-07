import SwiftUI

/// The single editor for a companion reminder (DESIGN R4/R7). Writes the reminder
/// half (title/notes/due/priority/list/early-reminder alarm) back to Apple Reminders
/// through `TaskService`, and the estimated duration to the local sidecar. Recurrence
/// is read-only (R-recurrence): a repeating reminder shows a note but is edited in
/// Apple Reminders.
///
/// With `includeRating` (used by Browse Completed, R6.5) the editor also shows a
/// **rating section below** the reminder fields — so a completed reminder's fields
/// (edit) and its performance (rate) are captured together in one screen — and Save
/// writes both the reminder (R4) and the rating/durations (R6.2).
struct CompanionReminderEditor: View {
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    /// The item being edited, or `nil` for a new reminder.
    private let existing: TaskItem?
    /// Whether to show the rating section below (only meaningful for an existing item).
    private let includeRating: Bool

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

    // Rating fields (shown only when `includeRating` and editing an existing item).
    @State private var rating: Int
    @State private var actualText: String
    @State private var perfNotes: String

    /// True when the rating section should show (edit-on-top, rate-below).
    private var showRating: Bool { includeRating && existing != nil }

    init(item: TaskItem? = nil, includeRating: Bool = false) {
        self.existing = item
        self.includeRating = includeRating
        _title = State(initialValue: item?.title ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _priority = State(initialValue: item?.priority ?? .none)
        _listId = State(initialValue: item?.listId ?? "")
        _hasDue = State(initialValue: item?.dueDate != nil)
        _dueDate = State(initialValue: item?.dueDate ?? DateTimeUtilities.time(hour: 9, minute: 0))
        _hasDueTime = State(initialValue: item?.hasDueTime ?? false)
        let firstAlarm = item?.alarmOffsetMinutes.first
        _hasAlarm = State(initialValue: firstAlarm != nil)
        _alarmMinutes = State(initialValue: firstAlarm ?? 15)
        _customLead = State(initialValue: firstAlarm.map { !ReminderLead.isPreset($0) } ?? false)
        _estimatedText = State(initialValue: item?.estimatedDuration.map(String.init) ?? "")
        _rating = State(initialValue: item?.rating ?? 50)
        _actualText = State(initialValue: item?.actualDuration.map(String.init) ?? "")
        _perfNotes = State(initialValue: item?.performanceNotes ?? "")
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

                if showRating {
                    Section("Performance") {
                        SliderField(title: "Rating", value: $rating)
                    }
                    Section("Actual duration (minutes)") {
                        TextField("Actual", text: $actualText).keyboardType(.numberPad)
                            .accessibilityIdentifier("ratingActualField")
                    }
                    Section("Performance notes") {
                        TextField("Notes", text: $perfNotes, axis: .vertical)
                            .accessibilityIdentifier("performanceNotesField")
                    }
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
        // Light-touch date/time: a "Date" toggle reveals a calendar, and only then a
        // "Time" toggle reveals a time picker — nothing shows until you opt in.
        Section {
            Toggle(isOn: $hasDue.animation()) { Label("Date", systemImage: "calendar") }
                .accessibilityIdentifier("dueToggle")
            if hasDue {
                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .accessibilityIdentifier("datePicker")

                Toggle(isOn: $hasDueTime.animation()) { Label("Time", systemImage: "clock") }
                    .accessibilityIdentifier("dueTimeToggle")
                if hasDueTime {
                    DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("timePicker")
                }
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
                if showRating {
                    // Combined edit-on-top / rate-below: one write for estimate + rating.
                    await taskService.recordRating(
                        id: id, rating: rating, notes: perfNotes.isEmpty ? nil : perfNotes,
                        estimatedMinutes: estimated, actualMinutes: Int(actualText)
                    )
                } else {
                    await taskService.setEstimatedDuration(id: id, minutes: estimated)
                }
            }
            dismiss()
        }
    }

    private func delete() {
        guard let id = existing?.id else { return }
        Task { await taskService.delete(id: id); dismiss() }
    }
}
