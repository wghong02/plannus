import SwiftUI

/// A top-bar menu that filters a surface by Reminders list (DESIGN R6.5 / D16);
/// `selection == nil` ⇒ **All Lists**. Shared by the Completed and Performance tabs
/// so the control looks and behaves the same in both. The icon fills when a filter
/// is active.
struct ListFilterMenu: View {
    let lists: [ReminderList]
    @Binding var selection: String?
    let identifier: String

    var body: some View {
        Menu {
            Picker("List", selection: $selection) {
                Text("All Lists").tag(String?.none)
                ForEach(lists) { list in
                    Text(list.title).tag(String?.some(list.id))
                }
            }
        } label: {
            Label("Filter by list",
                  systemImage: selection == nil ? "line.3.horizontal.decrease.circle"
                                                 : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier(identifier)
    }
}
