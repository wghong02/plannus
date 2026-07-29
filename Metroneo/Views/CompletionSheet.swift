import SwiftUI

/// Shown on **every** completion (DESIGN.md §7.2, renamed from the rating sheet).
/// Always captures the actual duration (defaulting to the estimate); if the entry
/// is ratable it also offers a **skippable** rating — completing never forces one
/// (D6.3).
struct CompletionSheet: View {
    @EnvironmentObject private var entryService: EntryService
    @Environment(\.dismiss) private var dismiss

    let entry: Entry

    @State private var actualText: String
    @State private var rate: Bool
    @State private var ratingValue: Int

    init(entry: Entry) {
        self.entry = entry
        // Actual duration defaults to the planned (estimated) duration, blank if none.
        _actualText = State(initialValue: entry.estimatedDuration.map(String.init) ?? "")
        _rate = State(initialValue: entry.isRatable)
        _ratingValue = State(initialValue: entry.rating?.performanceRating ?? 50)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual duration (minutes)") {
                    TextField("Actual", text: $actualText).keyboardType(.numberPad)
                }
                if entry.isRatable {
                    Section("Performance") {
                        Toggle("Rate this", isOn: $rate)
                        if rate { SliderField(title: "Rating", value: $ratingValue) }
                    }
                }
            }
            .navigationTitle("Complete “\(entry.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { complete() } }
            }
        }
    }

    private func complete() {
        entryService.setActualDuration(id: entry.id, minutes: Int(actualText))
        if entry.isRatable, rate {
            entryService.rateEntry(id: entry.id, performance: ratingValue)
        }
        entryService.completeEntry(id: entry.id)
        dismiss()
    }
}
