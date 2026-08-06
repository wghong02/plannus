import Foundation
import WidgetKit

/// Persists a snapshot to the shared App Group and asks WidgetKit to reload, so the
/// widgets update whenever the app's read model changes (DESIGN — Widgets).
final class AppWidgetPublisher: WidgetSnapshotPublishing {
    func publish(_ snapshot: WidgetSnapshot) {
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
