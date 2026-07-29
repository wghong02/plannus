import Foundation

/// The repeat unit of a recurring series (D15.1).
public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily, weekly, monthly, yearly
}

/// When a series stops (D15.1). There is **no** "never" — a series is always
/// finite, which keeps pre-generation complete.
public enum RecurrenceEnd: Codable, Equatable, Hashable, Sendable {
    /// Generate every occurrence whose date is on or before this day.
    case until(Date)
    /// Generate exactly this many occurrences (must be ≥ 1).
    case afterCount(Int)
}

/// A recurrence rule (D15.1): "every `interval` `frequency`" until `end`.
/// Replaces the legacy `frequencyPattern`/`frequencyCount`/`recurring`/`custom`
/// fields — `custom` collapses into `daily` with an arbitrary `interval`.
public struct RecurrenceRule: Codable, Equatable, Hashable, Sendable {
    public var frequency: RecurrenceFrequency
    /// ≥ 1 (clamped on init).
    public var interval: Int
    public var end: RecurrenceEnd

    public init(frequency: RecurrenceFrequency, interval: Int = 1, end: RecurrenceEnd) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.end = end
    }
}

/// A recurring series (D15): its rule plus the `template` every occurrence is
/// built from. Occurrences are ordinary ``Entry`` values carrying this `id` as
/// their `seriesId`. The template is the canonical generator (edited by the
/// "All" scope, D15.6) and is stored so regeneration never has to invert a
/// clamped date.
public struct Series: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var rule: RecurrenceRule
    public var template: Entry

    public init(id: String = UUID().uuidString, rule: RecurrenceRule, template: Entry) {
        self.id = id
        self.rule = rule
        self.template = template
    }
}

/// Pure occurrence generation (D15.2/D15.3). Each occurrence is a fully
/// independent entry (fresh id, own `occurrenceIndex`, reset tracking) with its
/// dates offset from the template. Month/year clamping follows **RFC 5545**: by
/// always offsetting from the *original* template date, Jan 31 monthly yields
/// Feb 28 → **Mar 31** (anchor preserved, no drift).
public enum RecurrenceEngine {

    /// Generates the entries of a series (occurrence 0 = the template's own date).
    public static func generate(series: Series, calendar: Calendar = .current) -> [Entry] {
        generate(template: series.template, rule: series.rule, seriesId: series.id, calendar: calendar)
    }

    public static func generate(
        template: Entry,
        rule: RecurrenceRule,
        seriesId: String,
        calendar: Calendar = .current
    ) -> [Entry] {
        occurrenceSteps(template: template, rule: rule, calendar: calendar).map { step in
            occurrence(template: template, step: step, seriesId: seriesId, rule: rule, calendar: calendar)
        }
    }

    /// The occurrence indices this rule produces (0-based; always includes 0).
    static func occurrenceSteps(template: Entry, rule: RecurrenceRule, calendar: Calendar) -> [Int] {
        switch rule.end {
        case .afterCount(let n):
            return Array(0..<max(1, n))
        case .until(let end):
            guard let anchor = template.timeKey else { return [0] }
            let endDay = calendar.startOfDay(for: end)
            var steps = [0]
            var k = 1
            let safetyCap = 3660 // ~10y daily; guards against pathological rules
            while k < safetyCap {
                let occDate = offset(anchor, byStep: k, rule: rule, calendar: calendar)
                guard calendar.startOfDay(for: occDate) <= endDay else { break }
                steps.append(k)
                k += 1
            }
            return steps
        }
    }

    /// Builds occurrence `step` from `template`: dates offset, tracking reset to
    /// "not completed / not rated" (aspect presence preserved), fresh id.
    static func occurrence(
        template: Entry,
        step: Int,
        seriesId: String,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Entry {
        var e = template
        e.id = UUID().uuidString
        e.seriesId = seriesId
        e.occurrenceIndex = step
        e.actualDuration = nil
        if e.completion != nil { e.completion = Completion(completedAt: nil) }
        if e.rating != nil { e.rating = Rating(performanceRating: nil, performanceNotes: nil) }
        if let s = template.scheduled {
            e.scheduled = Schedule(
                start: offset(s.start, byStep: step, rule: rule, calendar: calendar),
                end: offset(s.end, byStep: step, rule: rule, calendar: calendar),
                allDay: s.allDay
            )
        }
        if let d = template.deadline {
            e.deadline = Deadline(
                date: offset(d.date, byStep: step, rule: rule, calendar: calendar),
                hasTime: d.hasTime
            )
        }
        return e
    }

    /// Offsets a date by `step` rule-steps from the original (preserves time-of-day;
    /// Calendar clamps invalid month days per RFC 5545).
    static func offset(_ date: Date, byStep step: Int, rule: RecurrenceRule, calendar: Calendar) -> Date {
        guard step != 0 else { return date }
        let (component, multiplier) = componentAndMultiplier(rule.frequency)
        let value = step * rule.interval * multiplier
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    private static func componentAndMultiplier(_ frequency: RecurrenceFrequency) -> (Calendar.Component, Int) {
        switch frequency {
        case .daily: return (.day, 1)
        case .weekly: return (.day, 7)
        case .monthly: return (.month, 1)
        case .yearly: return (.year, 1)
        }
    }
}
