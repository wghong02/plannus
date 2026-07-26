# Metroneo

Metroneo is a native iOS task and event planner with built-in performance
tracking, built in **Swift + SwiftUI** and backed by **SwiftData**.

Plan your day on a calendar, manage tasks with subtasks and priorities, rate how
well you performed as you complete them, and review your trends over time with
charts.

## Features

- **Calendar** — a native month calendar; for any day, see its events alongside
  the incomplete tasks due that day.
- **Tasks** — create/edit/delete tasks with notes, priority, deadline (date +
  optional time), recurrence, estimated duration, freeform type tags, and
  subtasks. Toggle between **Upcoming** and **Completed**. Completing a task
  requires its subtasks to be done and prompts for a performance rating.
- **Events** — date-anchored entries with optional start/end times or an
  all-day flag.
- **Performance** — analytics over completed tasks: pick a time period, see the
  count and average score, weekly/monthly line charts (Swift Charts), insight
  highlights, and a recent-tasks list with color-coded scores.
- **Settings** — customize the performance-rating cutoffs (Poor → Excellent).
  A developer-only Database Management panel is available in Debug builds.

See [`FUNCTIONALITY.md`](FUNCTIONALITY.md) for a complete, section-by-section
specification of every **current** behavior, and [`DESIGN.md`](DESIGN.md) for the
**target/eventual** behavior and the planned reworks.

## Requirements

- Xcode 16 or later
- iOS 16.0+ deployment target

## Getting started

```sh
open Metroneo.xcodeproj
```

Select the **Metroneo** scheme and an iOS Simulator (or a device), then Run
(⌘R). No third-party dependencies or package resolution are required — the app
uses only Apple frameworks (SwiftUI, SwiftData, Charts).

### Running the tests

Product ▸ Test (⌘U), or:

```sh
xcodebuild test -scheme Metroneo -destination 'platform=iOS Simulator,name=iPhone 15'
```

The `MetroneoTests` target covers the date/time utilities, the in-memory store,
the services, and the performance analytics.

## Architecture

The app separates a pure, testable domain layer from the SwiftUI presentation
layer. Persistence is SwiftData; an in-memory store configuration backs tests
and previews.

```
Metroneo/
├── App/          MetroneoApp (entry point), RootView (tab bar)
├── Models/       Task, SubTask, Event value types
├── Storage/      StoredModels (@Model classes) + SwiftDataDatabase
├── Services/     TaskService, EventService, PerformancePreferencesService,
│                 PerformanceAnalytics
├── Utilities/    DateTimeUtilities, Palette, Log
├── Views/        CalendarView, TaskListView, PerformanceView, SettingsView,
│                 and the task/event/rating sheets
└── Resources/    (no on-disk model — SwiftData persists the @Model classes)

MetroneoTests/     Unit tests for utilities, storage, services, analytics
```

- **Models** are `Codable`/`Identifiable` structs with no framework dependencies.
- **`SwiftDataDatabase`** is the sole persistence store. It maps the domain value
  types to/from three `@Model` classes — `StoredTask`, `StoredSubTask`,
  `StoredEvent` — and its `inMemory` initializer backs tests and previews. Saving
  tasks replaces the whole task + subtask set, preserving each incoming id.
- **Services** are `ObservableObject`s injected via the SwiftUI environment; they
  cache state and delegate persistence to `SwiftDataDatabase` (preferences use
  `UserDefaults`).
- **`PerformanceAnalytics`** holds the period filtering and weekly/monthly
  aggregation as pure functions.

## Data model at a glance

| Type | Key fields |
| --- | --- |
| `Task` | title, notes, deadline, priority/performance ratings (0–100), completedAt, createDate, recurrence, types, durations, subtasks |
| `SubTask` | title, ratings, deadline, completion, order within its parent |
| `Event` | id, date, title, notes, allDay, start/end time |

Dates and times are `Date` values; events are grouped by local start-of-day. A
task's `completedAt` is `nil` until it is completed.

## Project history

Metroneo began as a React Native / Expo app. That original implementation is
preserved on the **`old-expo-react-native`** branch; `master` is the native
Swift + SwiftUI rewrite.
