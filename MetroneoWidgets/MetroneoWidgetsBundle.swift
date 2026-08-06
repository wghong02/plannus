import WidgetKit
import SwiftUI

/// The widget extension entry point (DESIGN — Widgets). Lists all four widgets.
@main
struct MetroneoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TasksWidget()              // 1 — open reminders + complete circle (S/M)
        NeedsRatingWidget()        // 2 — completed-but-unrated reminders (S/M)
        PerformanceWidget()        // 3 — weekly performance / rated, with toggle (M)
        PerformanceLargeWidget()   // 4 — weekly performance AND rated (L)
    }
}
