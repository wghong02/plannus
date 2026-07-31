import SwiftUI

/// A single entry row shared by the Calendar and Tasks lists. Shows a completion
/// checkbox (completable entries), the title (struck through + dimmed when
/// completed), a timing/priority subtitle, and a recurrence badge.
struct EntryRow: View {
    let entry: Entry
    var onToggleComplete: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            if entry.isCompletable, let toggle = onToggleComplete {
                Button(action: toggle) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(entry.isCompleted ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("completeToggle")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .strikethrough(entry.isCompleted)
                Text(Self.subtitle(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isSeriesMember {
                Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
            }
            if entry.isRated, let r = entry.rating?.performanceRating {
                Text("\(r)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .opacity(entry.isCompleted ? 0.6 : 1)
    }

    static func subtitle(_ entry: Entry) -> String {
        var parts: [String] = []
        if let s = entry.scheduled {
            if s.allDay {
                parts.append("All day")
            } else {
                let f = Date.FormatStyle(date: .abbreviated, time: .shortened)
                parts.append(s.start.formatted(f))
            }
        }
        if let d = entry.deadline {
            parts.append("Due " + DateTimeUtilities.formatDeadline(d.date, hasTime: d.hasTime))
        }
        if parts.isEmpty { parts.append("Priority \(entry.priorityRating)") }
        return parts.joined(separator: " · ")
    }
}

/// A leading-toolbar filter control (D7.7). Binds an ``EntryFilter`` and offers
/// completion / tag / collection facets drawn from the current data.
struct FilterMenu: View {
    @Binding var filter: EntryFilter
    let tags: [String]
    let collections: [EntryCollection]

    var body: some View {
        Menu {
            Picker("Completion", selection: $filter.completion) {
                Text("All").tag(EntryFilter.CompletionState.any)
                Text("Upcoming").tag(EntryFilter.CompletionState.upcoming)
                Text("Completed").tag(EntryFilter.CompletionState.completed)
            }
            if !tags.isEmpty {
                Menu("Tag") {
                    Button("Any") { filter.tag = nil }
                    ForEach(tags, id: \.self) { tag in
                        Button { filter.tag = tag } label: {
                            Label(tag, systemImage: filter.tag == tag ? "checkmark" : "")
                        }
                    }
                }
            }
            if !collections.isEmpty {
                Menu("Collection") {
                    Button("Any") { filter.collectionMemberIds = nil }
                    ForEach(collections) { c in
                        Button { filter.collectionMemberIds = Set(c.memberIds) } label: { Text(c.name) }
                    }
                }
            }
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("filterMenu")
    }
}

extension EntryFilter {
    var isActive: Bool { completion != .any || tag != nil || collectionMemberIds != nil }
}
