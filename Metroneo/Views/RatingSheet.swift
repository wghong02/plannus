import SwiftUI

/// The dedicated rating sheet (DESIGN R6.2): a 0–100 rating slider (D11),
/// estimated + actual time capture, and notes. Saving writes the sidecar and drops
/// the item from the Needs-rating inbox. Capturing the **estimated** duration here
/// too (not only in the editor) means a completed reminder — which is only
/// reachable via this sheet — can still get both durations, so the
/// estimated-vs-actual bars (D17) actually populate.
struct RatingSheet: View {
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    let item: TaskItem
    @State private var rating: Int
    @State private var estimatedText: String
    @State private var actualText: String
    @State private var notes: String

    init(item: TaskItem) {
        self.item = item
        _rating = State(initialValue: item.rating ?? 50)
        _estimatedText = State(initialValue: item.estimatedDuration.map(String.init) ?? "")
        _actualText = State(initialValue: item.actualDuration.map(String.init) ?? "")
        _notes = State(initialValue: item.performanceNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Performance") {
                    SliderField(title: "Rating", value: $rating)
                }
                Section("Estimated duration (minutes)") {
                    TextField("Estimated", text: $estimatedText).keyboardType(.numberPad)
                        .accessibilityIdentifier("ratingEstimatedField")
                }
                Section("Actual duration (minutes)") {
                    TextField("Actual", text: $actualText).keyboardType(.numberPad)
                        .accessibilityIdentifier("ratingActualField")
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
                                id: item.id, rating: rating, notes: notes.isEmpty ? nil : notes,
                                estimatedMinutes: Int(estimatedText), actualMinutes: Int(actualText)
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
