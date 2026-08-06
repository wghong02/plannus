import SwiftUI

/// The dedicated rating sheet (DESIGNV2 R6.2) — the same shape as the old
/// completion sheet: a 0–100 rating slider (D11), actual-time capture, and notes.
/// Saving writes the sidecar and drops the item from the Needs-rating inbox.
struct RatingSheet: View {
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    let item: TaskItem
    @State private var rating: Int
    @State private var actualText: String
    @State private var notes: String

    init(item: TaskItem) {
        self.item = item
        _rating = State(initialValue: item.rating ?? 50)
        // Default the actual to a recorded actual, else the estimate.
        _actualText = State(initialValue: (item.actualDuration ?? item.estimatedDuration).map(String.init) ?? "")
        _notes = State(initialValue: item.performanceNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Performance") {
                    SliderField(title: "Rating", value: $rating)
                }
                Section("Actual duration (minutes)") {
                    TextField("Actual", text: $actualText).keyboardType(.numberPad)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Rate “\(item.title)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await taskService.recordRating(
                                id: item.id, rating: rating,
                                notes: notes.isEmpty ? nil : notes, actualMinutes: Int(actualText)
                            )
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("saveRatingButton")
                }
            }
        }
    }
}
