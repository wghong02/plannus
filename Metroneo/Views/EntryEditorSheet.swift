import SwiftUI
import UserNotifications

/// The single editor for every entry (DESIGN.md §6.1+§7.1 merged). Presents the
/// union of schedule, deadline, recurrence, reminder, tracking, durations, types,
/// and collection membership. A completed entry additionally exposes its
/// completion fields (rating, actual duration, completion time). Editing a series
/// occurrence prompts for scope (This / This-and-future / All, D15.6).
struct EntryEditorSheet: View {
    @EnvironmentObject private var entryService: EntryService
    @EnvironmentObject private var collectionService: CollectionService
    @EnvironmentObject private var seriesService: SeriesService
    @EnvironmentObject private var reminderScheduler: ReminderScheduler
    @Environment(\.dismiss) private var dismiss

    private let existing: Entry?

    // Core
    @State private var title: String
    @State private var notes: String
    @State private var priority: Int

    // Tracking aspects (D6)
    @State private var completable: Bool
    @State private var ratable: Bool

    // Schedule (D6.5)
    @State private var hasSchedule: Bool
    @State private var allDay: Bool
    @State private var scheduleStart: Date
    @State private var scheduleEnd: Date

    // Deadline (D6.5)
    @State private var hasDeadline: Bool
    @State private var deadlineDate: Date
    @State private var deadlineHasTime: Bool

    // Recurrence (D15) — only offered for a new, non-series entry.
    @State private var repeats: Bool
    @State private var frequency: RecurrenceFrequency
    @State private var interval: Int
    @State private var endAfterCount: Bool
    @State private var endCount: Int
    @State private var endDate: Date

    // Reminder (D9)
    @State private var hasReminder: Bool
    @State private var reminderMinutes: Int

    // Durations (D14)
    @State private var estimatedText: String
    @State private var actualText: String

    // Types (D4)
    @State private var types: [String]
    @State private var newType: String = ""

    // Completion fields (shown when the entry is already completed)
    @State private var completedAt: Date
    @State private var ratingValue: Int

    // Collection membership (D5)
    @State private var memberOf: Set<String>

    // Series-scope prompt
    @State private var showScopeDialog = false
    @State private var validationMessage: String?

    init(entry: Entry? = nil, defaultDay: Date? = nil) {
        self.existing = entry
        let e = entry ?? EntryEditorSheet.blank(on: defaultDay)
        _title = State(initialValue: e.title)
        _notes = State(initialValue: e.notes ?? "")
        _priority = State(initialValue: e.priorityRating)
        _completable = State(initialValue: e.isCompletable)
        _ratable = State(initialValue: e.isRatable)
        _hasSchedule = State(initialValue: e.scheduled != nil)
        _allDay = State(initialValue: e.scheduled?.allDay ?? false)
        _scheduleStart = State(initialValue: e.scheduled?.start ?? (defaultDay ?? Date()))
        _scheduleEnd = State(initialValue: e.scheduled?.end ?? (defaultDay ?? Date()).addingTimeInterval(3600))
        // A calendar "Add" (defaultDay set, new entry) defaults to a deadline on
        // that day so the entry lands on the selected day (DESIGN.md §6).
        _hasDeadline = State(initialValue: e.deadline != nil || (entry == nil && defaultDay != nil))
        _deadlineDate = State(initialValue: e.deadline?.date ?? DateTimeUtilities.endOfDay(defaultDay ?? Date()))
        _deadlineHasTime = State(initialValue: e.deadline?.hasTime ?? false)
        _repeats = State(initialValue: false)
        _frequency = State(initialValue: .weekly)
        _interval = State(initialValue: 1)
        _endAfterCount = State(initialValue: true)
        _endCount = State(initialValue: 5)
        _endDate = State(initialValue: (defaultDay ?? Date()).addingTimeInterval(30 * 86400))
        _hasReminder = State(initialValue: e.reminderLeadMinutes != nil)
        _reminderMinutes = State(initialValue: e.reminderLeadMinutes ?? 15)
        _estimatedText = State(initialValue: e.estimatedDuration.map(String.init) ?? "")
        _actualText = State(initialValue: e.actualDuration.map(String.init) ?? "")
        _types = State(initialValue: e.types)
        _completedAt = State(initialValue: e.completion?.completedAt ?? Date())
        _ratingValue = State(initialValue: e.rating?.performanceRating ?? 50)
        _memberOf = State(initialValue: [])
    }

    private var isCompleted: Bool { existing?.isCompleted ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New Entry", text: $title)
                        .accessibilityIdentifier("entryTitleField")
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Priority") { SliderField(title: "Priority", value: $priority) }

                scheduleSection
                deadlineSection
                if existing == nil { recurrenceSection }
                if hasSchedule || hasDeadline { reminderSection }
                trackingSection
                durationSection
                if isCompleted { completedFieldsSection }
                typesSection
                collectionSection
            }
            .navigationTitle(existing == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { attemptSave() } label: { Image(systemName: "checkmark") }
                        .accessibilityIdentifier("saveEntryButton")
                }
            }
            .alert("Invalid Entry", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(validationMessage ?? "") }
            .confirmationDialog("Apply changes to…", isPresented: $showScopeDialog, titleVisibility: .visible) {
                Button("This Entry") { save(scope: .thisOnly) }
                Button("This and Future") { save(scope: .thisAndFuture) }
                Button("All in Series") { save(scope: .all) }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { memberOf = Set(collectionService.collections(containing: existing?.id ?? "").map(\.id)) }
        }
    }

    // MARK: - Sections

    private var scheduleSection: some View {
        Section {
            Toggle("Scheduled (time block)", isOn: $hasSchedule)
            if hasSchedule {
                Toggle("All Day", isOn: $allDay)
                if !allDay {
                    DatePicker("Start", selection: $scheduleStart)
                    DatePicker("End", selection: $scheduleEnd)
                }
            }
        }
    }

    private var deadlineSection: some View {
        Section {
            Toggle("Deadline (due by)", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("Due", selection: $deadlineDate, displayedComponents: deadlineHasTime ? [.date, .hourAndMinute] : [.date])
                Toggle("Set deadline time", isOn: $deadlineHasTime)
            }
        }
    }

    private var recurrenceSection: some View {
        Section("Recurrence") {
            Toggle("Repeats", isOn: $repeats)
            if repeats {
                Picker("Frequency", selection: $frequency) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Stepper("Every \(interval)", value: $interval, in: 1...52)
                Toggle("End after count", isOn: $endAfterCount)
                if endAfterCount {
                    Stepper("\(endCount) occurrences", value: $endCount, in: 1...365)
                } else {
                    DatePicker("Until", selection: $endDate, displayedComponents: [.date])
                }
            }
        }
    }

    private var reminderSection: some View {
        Section("Reminder") {
            if reminderScheduler.authorization == .denied {
                // No inert reminders — the control is gated on authorization (D9.3a).
                Toggle("Remind me", isOn: .constant(false)).disabled(true)
                Text("Enable notifications in Settings to use reminders.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Remind me", isOn: $hasReminder)
                    .onChange(of: hasReminder) { _, on in
                        if on, reminderScheduler.authorization == .notDetermined {
                            reminderScheduler.requestAuthorization()
                        }
                    }
                if hasReminder {
                    Picker("Lead time", selection: $reminderMinutes) {
                        ForEach(ReminderLead.presets, id: \.self) { Text(Self.leadLabel($0)).tag($0) }
                    }
                }
            }
        }
    }

    private var trackingSection: some View {
        Section("Tracking") {
            Toggle("Completable", isOn: $completable)
            Toggle("Ratable", isOn: $ratable)
        }
    }

    private var durationSection: some View {
        Section("Duration (minutes)") {
            TextField("Estimated", text: $estimatedText).keyboardType(.numberPad)
            TextField("Actual", text: $actualText).keyboardType(.numberPad)
        }
    }

    private var completedFieldsSection: some View {
        Section("Completion") {
            DatePicker("Completed", selection: $completedAt)
            if ratable { SliderField(title: "Rating", value: $ratingValue) }
        }
    }

    private var typesSection: some View {
        Section("Tags") {
            if !types.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(types, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                Button { types.removeAll { $0 == tag } } label: { Image(systemName: "xmark.circle.fill") }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                }
            }
            HStack {
                TextField("Add tag", text: $newType)
                Button("Add") { addTag() }.disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var collectionSection: some View {
        Section("Collections") {
            if collectionService.collections.isEmpty {
                Text("No collections yet").foregroundStyle(.secondary)
            }
            ForEach(collectionService.collections) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { memberOf.contains(collection.id) },
                    set: { on in if on { memberOf.insert(collection.id) } else { memberOf.remove(collection.id) } }
                ))
            }
        }
    }

    // MARK: - Save

    private func attemptSave() {
        if hasSchedule, !allDay, scheduleEnd <= scheduleStart {
            validationMessage = "End time must be after start time."
            return
        }
        if existing?.isSeriesMember == true {
            showScopeDialog = true
        } else {
            save(scope: .thisOnly)
        }
    }

    private func save(scope: SeriesScope) {
        var entry = existing ?? Entry()
        entry.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? "New Entry" : title
        entry.notes = notes.isEmpty ? nil : notes
        entry.priorityRating = priority
        entry.types = types
        entry.scheduled = hasSchedule
            ? Schedule(start: scheduleStart, end: allDay ? scheduleStart : scheduleEnd, allDay: allDay)
            : nil
        entry.deadline = hasDeadline ? Deadline(date: deadlineDate, hasTime: deadlineHasTime) : nil
        entry.reminderLeadMinutes = (hasReminder && (hasSchedule || hasDeadline)) ? reminderMinutes : nil
        entry.estimatedDuration = Int(estimatedText)
        entry.actualDuration = Int(actualText)
        // Tracking aspects: preserve recorded values where the aspect stays on.
        entry.completion = completable ? (entry.completion ?? Completion()) : nil
        entry.rating = ratable ? (entry.rating ?? Rating()) : nil
        if isCompleted {
            entry.completion?.completedAt = completedAt
            if ratable { entry.rating?.performanceRating = ratingValue }
        }

        if existing?.isSeriesMember == true {
            // `.all`/`.thisAndFuture` delete + regenerate the occurrence under a
            // fresh id, so sync membership onto the survivor edit() reports back —
            // not the (now-deleted) id we edited.
            let survivorId = seriesService.edit(entry, scope: scope)
            // Those deletes dropped the old ids from collections in the store;
            // refresh the cache so we don't re-persist a now-dangling member id.
            collectionService.loadCollections()
            syncMembership(for: survivorId ?? entry.id)
            dismiss(); return
        } else if existing == nil, repeats {
            let rule = RecurrenceRule(
                frequency: frequency, interval: interval,
                end: endAfterCount ? .afterCount(endCount) : .until(endDate)
            )
            let series = seriesService.createSeries(template: entry, rule: rule)
            // Attach the first occurrence to any chosen collections.
            if let first = entryService.entries.first(where: { $0.seriesId == series.id && $0.occurrenceIndex == 0 }) {
                syncMembership(for: first.id)
            }
            dismiss(); return
        } else {
            entryService.upsertEntry(entry)
        }
        syncMembership(for: entry.id)
        dismiss()
    }

    private func syncMembership(for entryId: String) {
        for collection in collectionService.collections {
            let shouldContain = memberOf.contains(collection.id)
            let contains = collection.contains(entryId)
            if shouldContain, !contains { collectionService.addMember(collectionId: collection.id, entryId: entryId) }
            if !shouldContain, contains { collectionService.removeMember(collectionId: collection.id, entryId: entryId) }
        }
    }

    private func addTag() {
        let t = newType.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !types.contains(t) else { newType = ""; return }
        types.append(t)
        newType = ""
    }

    // MARK: - Helpers

    private static func blank(on day: Date?) -> Entry { Entry() }

    private static func leadLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "At time"
        case 1..<60: return "\(minutes) min before"
        case 60: return "1 hour before"
        case 61..<1440: return "\(minutes / 60) hours before"
        case 1440: return "1 day before"
        default: return "\(minutes / 1440) days before"
        }
    }
}
