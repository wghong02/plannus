# Metroneo

Metroneo is a native iOS planner with built-in performance tracking, built in
**Swift + SwiftUI** and backed by **SwiftData**.

It collapses tasks and events into **one unit — the `Entry`**. An entry can be a
time block, a due-dated to-do, both, or neither; it can be completed and rated —
and you choose which. Group entries into Collections, repeat them on a schedule,
and review how you've performed over time.

## Features

- **Calendar** — a day picker driving that day's entries. A `scheduled` entry
  shows as an event on every day it spans; a `deadline` shows as a due marker.
  Completed entries stay, listed below the incomplete ones.
- **Tasks** — your working list, toggling between **All entries** and **By
  collection**. Create/edit entries with notes, priority, schedule, deadline,
  recurrence, reminder, durations, and tags; filter (top-left) and sort
  (top-right); complete an entry to log its actual duration and an optional
  rating.
- **Collections** — group entries **ordered** (drag to reorder) or **parallel**;
  membership is many-to-many, and deleting a collection never deletes its entries.
- **Recurrence** — a rule (every N days/weeks/months/years, until a date or after
  a count) pre-generates independent occurrences; edit/delete offers
  **This / This-and-future / All**.
- **Reminders** — a dated entry can fire a local notification ahead of its time;
  tapping it opens the Calendar to that day.
- **Performance** — analytics over **rated** entries: pick a period, see the
  count and average, a trend + distribution, insights, and a recent list, with
  user-customizable level labels, colors, and trend thresholds.
- **Settings** — the combined performance-customization screen (cutoffs, labels,
  colors, trend). A developer-only database panel is available in Debug builds.

See [`DESIGN.md`](DESIGN.md) for the full spec — the numbered requirements
(**D1–D16**), the rework tasks, and the test plan.

## Requirements

- Xcode 16 or later (Swift 5, uses only Apple frameworks: SwiftUI, SwiftData,
  Charts, UserNotifications)
- iOS 17.0+ deployment target

## Getting started

```sh
open Metroneo.xcodeproj
```

Select the **Metroneo** scheme and an iOS Simulator (or device), then Run (⌘R).
No third-party dependencies or package resolution required.

### Running the tests

Product ▸ Test (⌘U), or:

```sh
xcodebuild test -scheme Metroneo -destination 'platform=iOS Simulator,name=iPhone 16'
```

- **`MetroneoTests`** — unit + integration coverage of the models, storage,
  services, and the pure logic (sort/filter, calendar grouping, recurrence,
  trend, color).
- **`MetroneoUITests`** — XCUITest flows: create → display, complete,
  collections, calendar placement, plus tab/onboarding smoke checks.

Tests cite the DESIGN.md test-plan IDs with `// spec: <ID>` comments.

## Architecture

A pure, testable domain + logic layer sits under the SwiftUI presentation layer;
persistence is SwiftData (an in-memory configuration backs tests).

```
Metroneo/
├── App/          MetroneoApp (entry point), RootView (tab bar)
├── Models/       Entry (+ Schedule/Deadline/Completion/Rating), EntryCollection,
│                 RecurrenceRule/Series + RecurrenceEngine
├── Storage/      StoredEntryModels (@Model classes) + EntryDatabase
├── Services/     Entry/Collection/Series services, performance preferences +
│                 customization, EntryQuery, CalendarGrouping, TrendClassifier,
│                 ReminderScheduler, OnboardingGate, PerformanceAnalytics
├── Utilities/    DateTimeUtilities, ColorHex, Palette, Log
└── Views/        Calendar, Tasks (+collections), Performance, Settings, the
                  entry editor, completion sheet, onboarding, shared rows
```

- **Models** are `Codable`/`Identifiable` value types with no framework
  dependencies. Completion and rating are **independent optional aspects** — an
  entry is checkable only if it has a `completion`, ratable only if it has a
  `rating`, and each holds an optional recorded value.
- **`EntryDatabase`** is the sole store. It maps the value types to/from
  `@Model` classes and writes **per-entity** (`upsertEntry`/`deleteEntry`), never
  the whole set; its `inMemory` initializer backs tests.
- **Services** are `ObservableObject`s injected via the environment; each mutation
  updates the in-memory copy in place and persists the one entity (preferences use
  `UserDefaults`).
- **Pure logic** (`EntryQuery`, `CalendarGrouping`, `RecurrenceEngine`,
  `TrendClassifier`, `ColorHex`, `PerformanceAnalytics`) is extracted from the
  views so it's unit-testable without a running app.

## Data model at a glance

| Type | Key fields |
| --- | --- |
| `Entry` | title, notes, types, priority, createDate, durations, `scheduled?` (start/end/allDay), `deadline?` (date/hasTime), `reminderLeadMinutes?`, `completion?`, `rating?`, `seriesId?`/`occurrenceIndex?` |
| `EntryCollection` | name, ordering (ordered/parallel), `memberIds` (M2M, de-duplicated) |
| `Series` | recurrence rule + template entry (occurrences are ordinary entries) |

Dates and times are `Date` values; the calendar groups entries by local
start-of-day.

## Project history

Metroneo began as a React Native / Expo app (preserved on the
**`old-expo-react-native`** branch), was rewritten in native Swift + SwiftUI, and
then rebuilt around the unified `Entry` model described in
[`DESIGN.md`](DESIGN.md).
