import SwiftUI

/// The modal an entry list can present. Enum-driven so a single `.sheet(item:)`
/// handles add / edit / complete without competing sheet modifiers.
enum EntrySheet: Identifiable {
    case add(day: Date?)
    case edit(Entry)
    case complete(Entry)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let e): return "edit-\(e.id)"
        case .complete(let e): return "complete-\(e.id)"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .add(let day): EntryEditorSheet(defaultDay: day)
        case .edit(let entry): EntryEditorSheet(entry: entry)
        case .complete(let entry): CompletionSheet(entry: entry)
        }
    }
}
