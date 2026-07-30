import SwiftUI

/// First-run walkthrough of the main features (D13). Shown once (a `UserDefaults`
/// "seen" flag), skippable, and replayable from Settings.
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(icon: "square.stack.3d.up",
             title: "One planner, one Entry",
             body: "Everything you plan is a single Entry. Give it a time block, a due date, both, or neither — and choose whether to track and rate it."),
        Page(icon: "calendar",
             title: "Calendar & Tasks",
             body: "Scheduled entries appear on the Calendar; the Tasks tab is your working list and switches between All entries and By collection."),
        Page(icon: "checkmark.seal",
             title: "Complete & rate",
             body: "Check anything off. Completing opens a quick sheet to log how long it took and, optionally, rate how it went."),
        Page(icon: "chart.bar",
             title: "Performance & customization",
             body: "Ratings feed the Performance tab. In Settings you can rename levels, recolor them, and tune the trend thresholds."),
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 24) {
                        Image(systemName: item.icon)
                            .font(.system(size: 72))
                            .foregroundStyle(.blue)
                        Text(item.title).font(.title).bold().multilineTextAlignment(.center)
                        Text(item.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == pages.count - 1 ? "Get Started" : "Next") {
                if page == pages.count - 1 { onDone() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom)

            Button("Skip", action: onDone)
                .font(.footnote)
                .padding(.bottom)
        }
    }
}
