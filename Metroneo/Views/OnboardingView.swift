import SwiftUI

/// First-run walkthrough (DESIGN D13): three paged cards that explain the
/// Reminders companion, ending in the Reminders access request (R1.1). Shown once
/// via ``OnboardingGate``; "Connect Reminders" grants access, marks the gate seen,
/// and dismisses. If access is declined, ``ReminderAccessGate`` still offers a
/// grant prompt.
struct OnboardingView: View {
    @EnvironmentObject private var taskService: TaskService

    /// Called when the walkthrough finishes (Connect or Skip) so the host can mark
    /// the gate seen and dismiss.
    let onFinish: () -> Void

    @State private var page = 0

    private struct Card {
        let symbol: String
        let title: String
        let body: String
    }

    private let cards = [
        Card(symbol: "checklist",
             title: "Your reminders, leveled up",
             body: "Metroneo connects to Apple Reminders and layers performance tracking on top — a rating and estimated-vs-actual time for everything you do."),
        Card(symbol: "star",
             title: "Rate what you finish",
             body: "Complete a reminder anywhere — here, in Reminders, or with Siri. Metroneo gathers the finished ones into a Needs-rating inbox so you can score them and log the time later."),
        Card(symbol: "chart.line.uptrend.xyaxis",
             title: "See how you're doing",
             body: "Your ratings become trends, level distributions, and estimated-vs-actual time — a self-review built from the tasks you already keep."),
    ]

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip") { onFinish() }
                    .accessibilityIdentifier("onboardingSkip")
            }
            .padding(.horizontal)

            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    cardView(card).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if page < cards.count - 1 {
                Button("Next") { withAnimation { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboardingNext")
            } else {
                Button("Connect Reminders") {
                    Task { _ = await taskService.requestAccess(); onFinish() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboardingGetStarted")
            }
        }
        .padding(.bottom, 32)
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 24) {
            Image(systemName: card.symbol)
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text(card.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(card.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding()
    }
}
