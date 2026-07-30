import Foundation

/// Pure calendar placement for entries (DESIGN.md D6.5 / EGRP-*). Replaces the
/// old `incompleteTasks(_:forDate:)` — an entry lands on a day by its `deadline`
/// day and/or **every** day its `scheduled` block spans, and completion does
/// **not** filter placement.
public enum CalendarGrouping {

    /// The local start-of-day keys an entry occupies:
    /// - the deadline's day, and
    /// - every day from `startOfDay(scheduled.start)` through `startOfDay(scheduled.end)`.
    public static func days(of entry: Entry, calendar: Calendar = .current) -> [Date] {
        var result = Set<Date>()
        if let s = entry.scheduled {
            var day = calendar.startOfDay(for: s.start)
            let last = calendar.startOfDay(for: s.end)
            var guardCount = 0
            while day <= last && guardCount < 4000 {
                result.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardCount += 1
            }
        }
        if let d = entry.deadline {
            result.insert(calendar.startOfDay(for: d.date))
        }
        return result.sorted()
    }

    /// The entries that land on `day`, in within-day display order (EGRP-05):
    /// incomplete first — timed scheduled (by start time) → all-day scheduled →
    /// deadline-only (by deadline time, timeless last) — then completed below in
    /// the same sub-order; ties by title then id. An entry both scheduled and due
    /// on the day appears once, in the scheduled bucket (EGRP-06).
    public static func entries(_ entries: [Entry], on day: Date, calendar: Calendar = .current) -> [Entry] {
        let key = calendar.startOfDay(for: day)
        let onDay = entries.filter { days(of: $0, calendar: calendar).contains(key) }
        return onDay.sorted { a, b in
            let ka = sortKey(a, on: key, calendar: calendar)
            let kb = sortKey(b, on: key, calendar: calendar)
            if ka.bucket != kb.bucket { return ka.bucket < kb.bucket }
            if ka.category != kb.category { return ka.category < kb.category }
            if ka.minutes != kb.minutes { return ka.minutes < kb.minutes }
            let ta = a.title.lowercased(), tb = b.title.lowercased()
            if ta != tb { return ta < tb }
            return a.id < b.id
        }
    }

    /// All entries grouped by their day key (a day with none is simply absent).
    public static func groupedByDay(_ entries: [Entry], calendar: Calendar = .current) -> [Date: [Entry]] {
        var groups: [Date: [Entry]] = [:]
        for entry in entries {
            for day in days(of: entry, calendar: calendar) {
                groups[day, default: []].append(entry)
            }
        }
        for (day, list) in groups {
            groups[day] = list.sorted { a, b in
                let ka = sortKey(a, on: day, calendar: calendar)
                let kb = sortKey(b, on: day, calendar: calendar)
                if ka.bucket != kb.bucket { return ka.bucket < kb.bucket }
                if ka.category != kb.category { return ka.category < kb.category }
                if ka.minutes != kb.minutes { return ka.minutes < kb.minutes }
                let ta = a.title.lowercased(), tb = b.title.lowercased()
                if ta != tb { return ta < tb }
                return a.id < b.id
            }
        }
        return groups
    }

    // MARK: - Within-day ordering key

    private struct DaySortKey {
        var bucket: Int    // 0 incomplete, 1 completed
        var category: Int  // 0 timed-scheduled, 1 all-day-scheduled, 2 deadline-only
        var minutes: Int   // time-of-day; timeless deadline pushed to the end
    }

    private static func sortKey(_ entry: Entry, on day: Date, calendar: Calendar) -> DaySortKey {
        let bucket = entry.isCompleted ? 1 : 0
        let scheduledOnDay = entry.scheduled.map { days(of: entry, calendar: calendar).contains(day) && $0.start <= $0.end } ?? false
        if let s = entry.scheduled, scheduledOnDay {
            if s.allDay {
                return DaySortKey(bucket: bucket, category: 1, minutes: 0)
            }
            return DaySortKey(bucket: bucket, category: 0, minutes: minutesOfDay(s.start, calendar: calendar))
        }
        // Deadline-only marker on this day.
        if let d = entry.deadline {
            let minutes = d.hasTime ? minutesOfDay(d.date, calendar: calendar) : Int.max
            return DaySortKey(bucket: bucket, category: 2, minutes: minutes)
        }
        return DaySortKey(bucket: bucket, category: 2, minutes: Int.max)
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
