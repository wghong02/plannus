# Metroneo — Functionality Reference

Metroneo is a native iOS task/event planner with performance tracking, written in
Swift + SwiftUI and persisted with **SwiftData**. This document catalogs every
functionality in the app as a list of **individually-testable behaviors**. The
source lives under `Metroneo/`; code comments reference section numbers here (e.g.
"FUNCTIONALITY.md §3").

---

## How to read this document

Each behavior has a **stable ID** and a **tag**:

- **ID** — e.g. `[TS-03]`. Cite it from a test with a `// spec: TS-03` comment so
  the doc and the suite stay traceable. IDs are append-only: never renumber; retire
  an ID by marking it *removed* rather than reusing it.

Behaviors describe current, shipped code. Target/eventual behavior and planned reworks
live in [DESIGN.md](DESIGN.md), not inline.
- **Tag**:
  - **(unit)** — pure logic, no I/O; testable directly.
  - **(integration)** — touches the SwiftData store or `UserDefaults`; test against
    an `inMemory` store / throwaway defaults suite.
  - **(ui)** — needs a running view. Some are pure logic currently trapped inside a
    `View` struct; those are flagged **pending extraction** — unit-testable once the
    logic is pulled into a helper, otherwise reachable only via XCUITest.
- Behaviors are stated as invariants, often **given/when/then**, with concrete
  example values and edge cases.

**ID prefixes:** `DM` domain models · `DB` persistence · `TS` TaskService ·
`ES` EventService · `PP` preferences · `DTU` date utilities · `PA` analytics ·
`CAL` calendar · `TE` task editor · `EE` event editor · `PR` rating sheet ·
`TL` tasks list · `PV` performance view · `SET` settings · `APP` bootstrap.

---

## 1. Overview

Bottom tab bar with four destinations:

| Tab | Purpose |
| --- | --- |
| **Calendar** | Month calendar; per-date list of **events** plus **incomplete tasks** due that day. |
| **Tasks** | Full task manager: create/edit/delete, subtasks, completion with performance rating, Upcoming/Completed toggle. |
| **Performance** | Analytics over completed tasks: period stats, trend charts, insights, recent list. |
| **Settings** | Personal Preferences → Performance Cutoffs; About/version; plus database management **in Debug builds only**. |

Three persisted domains: **Tasks** (+ **SubTasks**), **Events**, and
**Preferences** (performance cutoffs in `UserDefaults`).

---

## 2. Domain models

`Task`, `SubTask`, `Event` are Swift **value types** (`Codable`/`Identifiable`/
`Equatable`/`Hashable`). The store maps them to/from SwiftData `@Model` classes (§3).

### 2.1 Fields

**Task** — `id: String?`, `title: String`, `notes: String?`, `deadline: Date`,
`hasDeadlineTime: Bool`, `priorityRating: Int` (0–100), `performanceRating: Int`
(0–100), `completedAt: Date?`, `createDate: Date`, `frequencyPattern`
(`daily | weekly | monthly | yearly | custom | none`), `frequencyCount: Int`,
`recurring: Bool`, `types: [String]?`, `estimatedDuration: Int?` (min),
`actualDuration: Int?`, `performanceNotes: String?`, `subTasks: [SubTask]`.

**SubTask** — `id: String?`, `title`, `notes?`, `deadline: Date`,
`priorityRating`, `performanceRating`, `completedAt: Date?`,
`parentTaskId: String?`, `order: Int` (display order within the parent).

**Event** — `id: String` (required), `date: Date` (the event's day),
`title: String`, `notes: String?`, `allDay: Bool`, `startTime: Date?`,
`endTime: Date?`. `EventMap = [Date: [Event]]`.

### 2.2 Behaviors

- **[DM-01] (unit)** `Task.isCompleted == (completedAt != nil)`.
- **[DM-02] (unit)** `SubTask.isCompleted == (completedAt != nil)`.
- **[DM-03] (unit)** `Task` init defaults: `priorityRating 50`, `performanceRating 50`,
  `hasDeadlineTime false`, `frequencyPattern .none`, `frequencyCount 0`,
  `recurring false`, `completedAt nil`, `types nil`, `subTasks []`. (`deadline` and
  `createDate` are required; `createDate` defaults to `Date()`.)
- **[DM-04] (unit)** `Event.makeID(date:)` returns `"event-{millis}-{rand}"` where
  `millis = round(date.timeIntervalSince1970 * 1000)` and `rand ∈ [0, 1_000_000)`.
  *Example:* `makeID(date: Date(timeIntervalSince1970: 1))` → `"event-1000-<n>"`
  (exactly three `-`-separated parts).
- **[DM-05] (unit)** `id` is a stable UUID string assigned once and never reassigned
  across edits/saves (see [TS-01], [TS-04], [DB-02]).

---

## 3. Persistence (`SwiftDataDatabase`)

The sole store maps the value types to/from `@Model` classes `StoredTask`,
`StoredSubTask`, `StoredEvent`, with a **cascade** delete from a task to its
subtasks. An `inMemory` initializer backs tests. Everything persists natively
(`Int`, `Date`, `[String]`, the `FrequencyPattern` enum) — no `.xcdatamodeld`.

### 3.1 Tasks

- **[DB-01] (integration)** `saveTasks(set)` replaces the **whole** task + subtask
  set. *Given* a store holding tasks `[a, b]`, *when* `saveTasks([c])`, *then*
  `loadTasks()` returns exactly `[c]` (a, b and their subtasks are gone).
- **[DB-02] (integration)** `saveTasks` preserves each incoming task/subtask `id`;
  it mints a UUID only when the incoming `id` is `nil`.
- **[DB-03] (integration)** Blank/whitespace titles default on save: task →
  `"New Task"`, subtask → `"New Subtask"`.
- **[DB-04] (integration)** Each subtask's stored `orderIndex` is set from its array
  position; `loadTasks` returns subtasks sorted ascending by that order.
  *Example:* saving subtasks `[s0, s1, s2]` loads them back in that order with
  `order == [0, 1, 2]`.
- **[DB-05] (integration)** `loadTasks` returns tasks sorted by `createDate`
  **descending**.
- **[DB-06] (integration)** `types` round-trips: a non-empty array is preserved;
  both `nil` and `[]` load back as `nil`.
- **[DB-07] (integration)** `hasDeadlineTime` round-trips (`true` stays `true`;
  absent/`false` loads as `false`).
- **[DB-08] (integration)** Deleting or replacing tasks that **have subtasks** must
  not trip the cascade/inverse constraint. Tasks are deleted object-by-object so the
  cascade clears their subtasks (never a batch delete of children). Covers: re-saving
  over a subtasked task, and `reset()` with subtasks present.

### 3.2 Events

- **[DB-09] (integration)** `saveEvent` upserts by unique `eventID`: saving the same
  id twice updates in place — no duplicate row.
- **[DB-10] (integration)** `saveEvent` throws `MetroneoError.validation` when
  `title` is empty.
- **[DB-11] (integration)** `deleteEvent(id)` removes the matching event; an unknown
  id is a no-op (no throw).
- **[DB-12] (integration)** `loadEvents` returns events sorted by `date`, then
  `startTime`, then `title`.

### 3.3 Admin

- **[DB-13] (integration)** `reset()` clears all tasks, subtasks, and events;
  `stats()` afterward reports `taskCount == subTaskCount == eventCount == 0`.
- **[DB-14] (integration)** `stats()` reports accurate row counts, `schemaVersion == 1`,
  `isClosed == false`.
- **[DB-15] (integration)** Two `inMemory` stores are isolated. The initializer
  throws `MetroneoError.database` when the store fails to open (treated as fatal, §10).

---

## 4. Services

`TaskService`, `EventService`, `PerformancePreferencesService` are
`ObservableObject`s injected via the environment; they cache state and delegate to
`SwiftDataDatabase` (or `UserDefaults`).

### 4.1 TaskService

State: `@Published tasks: [Task]`. **Every mutation writes through to the store then
reloads** — no manual save step — so `tasks` always mirrors persisted state.

- **[TS-01] (integration)** `addTask(t)` mints a UUID `id` when `t.id == nil`,
  appends, and persists. *Given* an empty store, *when* `addTask(Task(title:"Write"))`,
  *then* a fresh `TaskService` on the same store loads one task titled "Write".
- **[TS-02] (unit)** Blank/whitespace titles default: task → `"New Task"`, subtask →
  `"New Subtask"` (mirrors [DB-03]).
- **[TS-03] (unit)** `addTask` assigns each subtask `order = arrayIndex` (0-based) and
  `parentTaskId = task.id`; pre-existing non-nil subtask ids are preserved; nil ids
  are minted.
- **[TS-04] (integration)** Id stability: an id captured after `addTask` is unchanged
  after any number of later mutations + reloads.
- **[TS-05] (integration)** `updateTask(u)` replaces only the task with `id == u.id`;
  count and other tasks unchanged.
- **[TS-06] (integration)** `deleteTask(id)` removes the task and (via store cascade)
  its subtasks; an unknown id is a no-op.
- **[TS-07] (integration)** `completeTask(id)` sets `completedAt` non-nil
  (⇒ `isCompleted`); `uncompleteTask(id)` resets it to `nil`.
- **[TS-08] (integration)** `updateTaskPerformance(id, p, notes?)` sets
  `performanceRating = p` and `performanceNotes = notes`; passing `notes: nil` clears
  the notes.
- **[TS-09] (integration)** `toggleSubTask(taskId, subTaskId)` flips that subtask's
  `completedAt` (`nil ↔ now`); sibling subtasks untouched; unknown ids are a no-op.
- **[TS-10] (unit)** Any mutation targeting a missing id leaves state unchanged
  (no crash).

### 4.2 EventService

Caches events grouped by local start-of-day (`[Date: [Event]]`). Edits persist
immediately.

- **[ES-01] (integration)** `addEvent(date, event)` normalizes the event to
  `startOfDay(date)` and re-anchors its start/end times onto that day (keeping the
  time-of-day). *Example:* adding "against" `2026-07-21T15:00` an event carrying
  `date 2026-01-05` and `startTime 09:30` stores `date = 2026-07-21` (start-of-day)
  and `startTime = 2026-07-21T09:30`.
- **[ES-02] (integration)** After `addEvent`, `events(on: date)` (keyed by
  start-of-day) includes it.
- **[ES-03] (integration)** `updateEvent` replaces the matching event (same id) in
  place, in both cache and store.
- **[ES-04] (integration)** `deleteEvent(date, id)` removes it and **prunes the day
  key** from the map when that day becomes empty.
- **[ES-05] (integration)** `loadEvents` groups all stored events by start-of-day;
  `events(on:)` for a day with none returns `[]`.

### 4.3 PerformancePreferencesService

Stores `PerformanceCutoffs { fair, good, veryGood, excellent }` in `UserDefaults`
under `@performance_cutoffs`.

- **[PP-01] (unit)** Defaults: `fair 60, good 75, veryGood 80, excellent 90`.
- **[PP-02] (unit)** `level(for:cutoffs:)` classifies highest-first with `>=`:
  `≥ excellent` → Excellent, else `≥ veryGood` → Very Good, else `≥ good` → Good,
  else `≥ fair` → Fair, else Poor. **Boundary:** a rating exactly at a cutoff belongs
  to the higher level. *Example (defaults):* `90 → Excellent`, `89 → Very Good`,
  `60 → Fair`, `59 → Poor`.
- **[PP-03] (unit)** `text(for:)` returns the level's raw string
  (`"Excellent" | "Very Good" | "Good" | "Fair" | "Poor"`).
- **[PP-04] (integration)** `setCutoffs(c)` persists to `UserDefaults`; a new service
  reading the same defaults loads `c`.
- **[PP-05] (integration)** With nothing stored, a new service starts at [PP-01].
- **[PP-06] (integration)** `resetToDefaults()` restores and persists [PP-01].

The fill `Color` for a level lives in `Palette.swift` (green → blue → orange → red);
surfaces use adaptive system colors (correct in dark mode).

---

## 5. Utility functions (`DateTimeUtilities`)

- **[DTU-01] (unit)** `startOfDay(d)` returns `d`'s local `00:00:00`.
- **[DTU-02] (unit)** `endOfDay(d)` returns `d` at `23:59:59` — the "due by end of
  day" default for date-only deadlines.
- **[DTU-03] (unit)** `combine(day, time)` returns `day`'s calendar date with
  `time`'s hour/minute (seconds 0); `time`'s date part is ignored. *Example:*
  `combine(Jul 21, 09:30-on-any-day)` → `Jul 21 T09:30`.
- **[DTU-04] (unit)** `time(hour, minute)` returns **today** at that hour/minute.
- **[DTU-05] (unit)** `shortDate(d)` is a localized **date-only** string (no time
  component).
- **[DTU-06] (unit)** `formatDeadline(deadline, hasTime:)` returns the short date,
  and appends `" at <time>"` **iff** `hasTime == true`.
- **[DTU-07] (unit)** `incompleteTasks(tasks, forDate:)` returns tasks with
  `completedAt == nil` whose `deadline` is the **same calendar day** as the target;
  completed tasks and other days are excluded; input order preserved.

Event start/end times display via SwiftUI's `Date.formatted`; there is no bespoke
time-string formatter.

---

## 6. Calendar tab (`CalendarView`)

- **[CAL-01] (ui)** Selecting a day drives a list of that day's **events** followed by
  its **incomplete tasks** (via [DTU-07]).
- **[CAL-02] (ui)** A day with neither shows "No events or tasks yet".
- **[CAL-03] (ui)** Tapping an event row opens the editor; swiping deletes it.
- **[CAL-04] (ui)** Task rows here are read-only (title, `Deadline: …`, notes,
  `Priority: N`), visually distinct.
- **[CAL-05] (ui)** The toolbar **+ Add Event** opens the event editor.

### 6.1 Event editor (`EventEditorSheet`)

- **[EE-01] (ui)** Fields: title (default "New Event"), **All Day** toggle (hides the
  time pickers when on), start/end time (`hour-and-minute` pickers), notes.
- **[EE-02] (ui — pending extraction)** Saving with an empty/whitespace title just
  dismisses without persisting.
- **[EE-03] (ui — pending extraction)** Save is blocked (alert "Invalid Time") unless
  `allDay` **or** `endTime > startTime`.
- **[EE-04] (ui — pending extraction)** On a valid save: `allDay` clears start/end
  (`nil`); editing preserves the event `id`; adding generates a new id; the service
  re-anchors times to the event's day ([ES-01]).

---

## 7. Tasks tab (`TaskListView`)

- **[TL-01] (ui — pending extraction)** **Upcoming** = not completed, sorted by
  `deadline` ascending; **Completed** = completed, sorted by `completedAt`
  descending; the segmented control shows each set's count.
- **[TL-02] (ui — pending extraction)** Completing a task with **any incomplete
  subtask** is blocked (alert); no state change.
- **[TL-03] (ui — pending extraction)** Completing an eligible task opens the rating
  sheet; saving sets `performanceRating` (+notes) **then** marks it complete
  (`completedAt = now`).
- **[TL-04] (ui)** Un-checking a completed task clears `completedAt`.
- **[TL-05] (ui)** A subtask checkbox toggles that subtask's `completedAt`.
- **[TL-06] (ui)** The card previews the first 2 subtasks, plus "+N more" when there
  are more than 2.
- **[TL-07] (ui)** Context menu: **Edit** always; **Edit Rating** only for completed
  tasks (reopens the rating sheet without changing completion).
- **[TL-08] (ui)** Swipe → **Delete**.
- **[TL-09] (ui)** Every action persists immediately — there is no Save button.

### 7.1 Task editor (`TaskEditorSheet`)

- **[TE-01] (ui)** Field defaults: title → "New Task" when blank, Priority 50,
  Performance 50, Create Date today, Deadline today, "set deadline time" off,
  Recurring off, Frequency Count 1 (editor).
- **[TE-02] (ui — pending extraction)** Deadline on save: "set deadline time" **off**
  → `endOfDay(day)` with `hasDeadlineTime = false`; **on** → `combine(day, time)`
  with `hasDeadlineTime = true`.
- **[TE-03] (ui — pending extraction)** When editing, `useDeadlineTime` is seeded from
  the task's `hasDeadlineTime`.
- **[TE-04] (ui — pending extraction)** Save builds a `Task` preserving existing
  `id`, `completedAt`, `performanceNotes`, and `actualDuration`; Recurring off forces
  `frequencyPattern = .none`; empty `types` → `nil`; `estimatedDuration` parses from
  text (`nil` when unparseable).
- **[TE-05] (ui)** Type chips add/remove (deduped, non-empty); subtasks add/remove
  (non-empty title, each seeded `deadline = endOfDay(deadlineDate)`).

### 7.2 Performance Rating (`PerformanceRatingSheet`)

- **[PR-01] (ui)** 0–100 slider; pre-filled with the task's `performanceRating` when
  the task is **completed**, else 50.
- **[PR-02] (ui — pending extraction)** Save emits `(Int(rating), notes?)`, where
  `notes` is `nil` when blank/whitespace.

---

## 8. Performance tab (`PerformanceView` + `PerformanceAnalytics`)

### 8.1 Analytics (`PerformanceAnalytics`, pure)

- **[PA-01] (unit)** `dateRange(for:now:)`: `end == now`; `start` = `now − 7d` (Week),
  `now − 1mo` (Month), `now − 3mo` (3 Months), `now − 1yr` (Year), epoch (All Time),
  `customStart` (Custom; defaults to `now − 7d` when `customStart` is nil).
- **[PA-02] (unit)** `filteredTasks` returns **completed** tasks whose `completedAt`
  ∈ `[alignedStart, now]`, where `alignedStart` is the begin of the **oldest trend
  bucket** — so stats and chart cover the same tasks.
- **[PA-03] (unit)** `average(tasks)` = mean of `performanceRating`; `0` for empty.
- **[PA-04] (unit)** `granularity` by span: `≤12d` daily, `≤62d` weekly, `≤168d`
  biweekly, `≤12mo` monthly, `≤36mo` quarterly, `≤72mo` half-year, else yearly.
  Fixed periods resolve to: Week→daily, Month→weekly, 3 Months→biweekly,
  Year→monthly. Custom uses its own start span; All Time uses the **earliest
  completion**.
- **[PA-05] (unit)** `trendSeries` yields buckets **oldest→newest**, capped at **12**;
  each window is half-open `[begin, end)`; the most recent bucket ends at
  **end-of-today** (so it includes today).
- **[PA-06] (unit)** A task is bucketed by `completedAt`; each bucket's `average` =
  mean of its tasks' ratings and `taskCount` = its count.
- **[PA-07] (unit)** Each bucket's `levelCounts` = per-`PerformanceLevel` counts using
  the supplied `cutoffs` (defaults if omitted). *Example (defaults):* ratings
  `[95, 82, 76, 61, 30]` → one each of Excellent/Very Good/Good/Fair/Poor; lowering
  `veryGood` to 70 reclassifies `76` as Very Good.
- **[PA-08] (unit)** Bucket labels: day-based (weekly/biweekly) use the window's
  **end** day (`"MMM d"`; most recent = today). Month-based are calendar-aligned:
  monthly `"MMM ''yy"`, quarterly `"QQQ ''yy"`, half-year `"H1/H2 ''yy"`,
  yearly `"yyyy"`.
- **[PA-09] (unit)** Consistency: `filteredTasks(...).count == Σ trendSeries(...).taskCount`
  for the same period + `now`.
- **[PA-10] (unit)** `best(series)` = the max-`average` bucket **among buckets with
  `taskCount > 0`**; `nil` when none qualify.
- **[PA-11] (unit)** `overallTrend(series)` compares the **first vs last non-empty**
  bucket average: `> +5%` → "Improving", `< −5%` → "Declining", within `±5%` →
  "Neutral"; `"N/A"` when fewer than 2 non-empty buckets. A zero first-bucket average
  → "Improving" if the last > 0, else "Neutral".

### 8.2 View (`PerformanceView`)

- **[PV-01] (ui)** Default period **Month**; the selector scopes the whole page
  (stats, charts, insights, list).
- **[PV-02] (ui)** Stat cards: tasks-completed count, and average performance to one
  decimal.
- **[PV-03] (ui)** Top line plot uses **monotone** interpolation (never overshoots
  above 100 / below 0); **empty buckets render as a gap** (not 0); dashed cutoff
  reference lines at each threshold.
- **[PV-04] (ui)** Bottom plot: per-bucket task count as a stacked bar segmented by
  category; shared legend (Excellent → Poor).
- **[PV-05] (ui — pending extraction)** Recent Performance list: up to 10 tasks
  sorted by `completedAt` **descending**; empty period → empty-state message.
- **[PV-06] (ui)** Insights: Best Period ([PA-10]), Overall Trend ([PA-11]), Best
  Rating (max rating in the period). Tap/drag the top plot to inspect a bucket; x
  labels rotate vertical past 8 buckets.

---

## 9. Settings tab (`SettingsView`)

- **[SET-01] (ui)** Root sections: **Personal Preferences** (all builds); **Database
  Management** (Debug only, `#if DEBUG`); **About** → read-only **Version** row
  `"<marketing> (<build>)"` from `CFBundleShortVersionString` / `CFBundleVersion`.
- **[SET-02] (ui)** Personal Preferences → **Performance Cutoffs**.
- **[SET-03] (ui — pending extraction)** Cutoffs **Save is rejected** (alert) when any
  value ∉ `0…100`, **or** when the values are not non-decreasing
  (`fair ≤ good ≤ veryGood ≤ excellent`); otherwise it persists and shows a success
  alert.
- **[SET-04] (ui)** **Reset to Defaults** restores the [PP-01] values.
- **[SET-05] (ui)** Database Management: **Database Test** (connection), **Database
  Stats** (row counts), **Erase All Data** (`reset()`).

---

## 10. App bootstrap (`MetroneoApp`)

- **[APP-01] (integration)** On launch the app constructs `SwiftDataDatabase`; a
  store-open failure is **fatal** (no fallback).
- **[APP-02] (integration)** Services are injected via the environment; tasks + events
  load before the tabs appear.
- **[APP-03]** The app icon is a single-size 1024×1024 `metroneo.png` in
  `Assets.xcassets/AppIcon.appiconset` (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`);
  `AccentColor` supplies the tint.

---

## 11. Architecture summary

- **Models** (`Metroneo/Models`) — `Task`, `SubTask`, `Event` value types.
- **Storage** (`Metroneo/Storage`) — `SwiftDataDatabase` (single engine) + the
  `@Model` types in `StoredModels`. No persistence protocol.
- **Services** (`Metroneo/Services`) — `TaskService`, `EventService`,
  `PerformancePreferencesService`, and `PerformanceAnalytics` (pure calculations).
- **Utilities** (`Metroneo/Utilities`) — `DateTimeUtilities`, `Palette`, `Log`.
- **Views** (`Metroneo/Views` + `Metroneo/App`) — `RootView`, `CalendarView`,
  `TaskListView`, `PerformanceView`, `SettingsView` + sub-screens, and the
  task/event/rating sheets.
- **Assets** (`Metroneo/Assets.xcassets`) — `AppIcon` + `AccentColor`.
- **Tests** (`MetroneoTests`) — cover the utilities, store, services, and analytics.
  Tests cite the behavior IDs above via `// spec: <ID>` comments; behaviors tagged
  **(ui)** are covered by XCUITest or become **(unit)** once their logic is extracted
  from the view.

---

## Appendix A — Coverage matrix (spec → test)

Tracks which behaviors have a test today. Update alongside the suite.

| Area | Behaviors | Covered today | Gap |
| --- | --- | --- | --- |
| Domain models | DM-01…05 | DM-04 | DM-01/02/03/05 |
| Persistence | DB-01…15 | DB-01,02,03,04,05,06,07,08,09,10,12,13,14 | DB-11 (unknown-id delete no-op), DB-15 (store isolation / throwing init) |
| TaskService | TS-01…10 | TS-01,02,03,04,05,06,07,08,09 | TS-10 (missing-id no-op) |
| EventService | ES-01…05 | ES-01,02,03,04,05 | — |
| Preferences | PP-01…06 | PP-01,02,03,04,05,06 | — |
| DateTimeUtilities | DTU-01…07 | DTU-01,02,03,04,05,06,07 | — |
| Analytics | PA-01…11 | PA-01,03,04,05,06,07,08,09,10,11 | PA-02 (aligned-window direct) |
| Views (CAL/TL/TE/EE/PR/PV/SET) | — | none | all (ui / pending extraction) |

*This matrix is the backlog for the "tests after" pass; treat any "Gap" cell as a
test to add.*
