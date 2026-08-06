# Metroneo — Design Notes (V2: Apple Reminders companion)

The **spec for the pivot**: Metroneo becomes a **companion to Apple Reminders** — it reads and
writes the user's real reminders (via EventKit) and layers a **performance-tracking** experience on
top. This document supersedes `DESIGN.md` for everything about the data layer; the parts of the old
spec that survive unchanged (the analytics + customization) are **carried over by reference** rather
than re-copied, so `DESIGN.md` remains the detailed source for those.

Three parts, mirroring `DESIGN.md`:

- **Vision** — how the companion works as a whole.
- **Target behavior** — the requirements. New companion requirements are numbered **`R1…Rn`**;
  requirements **carried over unchanged** keep their old **`Dn`** ids and point back to `DESIGN.md`.
- **Migration** — what to build, adapt, and delete, and in what order.

Decisions locked (from the pivot discussion): **full read/write companion**; **no events/time
blocks** (Reminders has no event concept); **Apple Reminders lists are the grouping** (they *are*
the old Collections — no separate tags); **priority = Apple's 4 buckets**; **ratings are captured via
a "Needs rating" inbox** (completion can happen anywhere); **no Calendar tab** (Apple's Reminders
already has a date-grouped Scheduled list). Later refinements: **default list scope = the user's
Reminders default list** (broadenable), and new reminders Metroneo creates go there; the **Needs-rating
window is a user-configurable slider** fed by the Reminders app's completion data; **recurrence stays
read-only**; the **sidecar is a SwiftData store**.

---

## Vision — Metroneo as a Reminders companion

Metroneo stops being a standalone planner with its own store and becomes a **performance layer over
the reminders you already keep.** Your tasks live in Apple Reminders — created there, or in Metroneo,
or by Siri/widgets, and synced by iCloud across your devices. Metroneo adds the one thing Apple
doesn't: **how well you did.**

- **Apple owns the task; Metroneo owns the performance.** A reminder's title, notes, due date,
  list, priority, alarms, recurrence, and completion are Apple's. Metroneo attaches a **rating**,
  **performance notes**, and an **estimated / actual time** to each reminder, stored locally and
  joined by the reminder's stable id.
- **Same reminders, everywhere.** Because the source of truth is Apple Reminders, Metroneo needs no
  sync, no notification scheduling, and no recurrence engine of its own — completing a reminder in
  Siri shows up in Metroneo, and completing one in Metroneo shows up in Reminders.
- **Rate after the fact.** Since a reminder can be finished anywhere, Metroneo surfaces a **Needs
  rating** inbox of recently-completed, still-unrated reminders — rate them and log the actual time
  when you get to it. The performance analytics span everything you've rated.
- **Two tabs of value + settings.** **Tasks** is your reminders (grouped by list) plus the
  Needs-rating inbox; **Performance** charts your rated reminders over time (the whole analytics
  suite, unchanged); **Settings** is the customization + Reminders access.

The result: a focused app that turns Apple Reminders into a self-review tool — trend lines,
level distributions, estimated-vs-actual time — without asking anyone to move their tasks.

---

## Architecture

Two data sources, joined at read time:

```
Apple Reminders (EventKit, EKEventStore)          Local performance sidecar (Metroneo)
  EKCalendar  (a reminder "list")                   keyed by reminder externalId:
  EKReminder  title, notes, dueDateComponents,        { rating: Int?, performanceNotes: String?,
              isCompleted, completionDate,               estimatedDuration: Int?,   // minutes
              priority, calendar(list),                  actualDuration: Int? }
              alarms, recurrenceRules,
              calendarItemExternalIdentifier
                              \                      /
                               →  TaskItem (read model, the join)  →  Performance analytics
```

- **`ReminderStore` protocol** wraps EventKit so nothing above it touches `EKEventStore` directly:
  fetch lists, fetch reminders (matching predicates), save / complete / delete a reminder, create /
  save a list, and observe external changes. A real `EventKitReminderStore` backs the app; a
  `FakeReminderStore` (in-memory) backs the tests, so the join / sidecar / analytics logic is fully
  unit-testable **without** the system store or its permission prompt. *(The same injection trick as
  today's `-UITEST-RESET`: launch the app with a fake store for UI tests.)*
- **`PerformanceSidecarStore`** persists the sidecar locally (per-entry writes, keyed by
  externalId) and **reconciles orphans** — sidecar rows whose reminder no longer exists are pruned
  on sync.
- **`TaskItem`** is the value-type projection the UI and analytics consume — an `EKReminder`'s
  relevant fields merged with its sidecar row.

### Field mapping (old `Entry` → companion source)

| Metroneo v2 (`Entry`) | Companion source | Notes |
| --- | --- | --- |
| `title`, `notes` | `EKReminder.title` / `.notes` | read/write |
| `deadline` (+ hasTime) | `EKReminder.dueDateComponents` | read/write; a components w/o time = date-only |
| `scheduled` (time block), `allDay`, `isEvent` | — | **removed** (Reminders has no events) |
| `completion` / `completedAt` | `EKReminder.isCompleted` / `.completionDate` | read/write |
| `types` (tags) | — | **removed**; lists are the grouping |
| Collections (`EntryCollection`) | **Reminders lists** (`EKCalendar`) | read/write (create list, move reminder) |
| `reminderLeadMinutes` / early reminder | `EKReminder.alarms` (`EKAlarm.relativeOffset`) | read/write; a negative offset = "before" |
| `seriesId` / recurrence | `EKReminder.recurrenceRules` | read/write; **aggregate** perf only (see R8) |
| `priorityRating` (0–100) | `EKReminder.priority` (None/Low/Medium/High) | read/write; 4 buckets (R7) |
| `estimatedDuration`, `actualDuration` | **sidecar** | minutes; local (R3) |
| `rating.performanceRating`, `.performanceNotes` | **sidecar** | local (R3) |
| `createDate`, `id` | `EKReminder.creationDate`, `.calendarItemExternalIdentifier` | id is the sidecar key |

---

## Target behavior

### R1 — EventKit access · proposal · depends: —
- **R1.1** — Metroneo requests **full access to Reminders** (`EKEventStore.requestFullAccessToReminders`,
  iOS 17+) with an `NSRemindersFullAccessUsageDescription`. Access is requested during onboarding
  and re-checked on launch; when denied, the app shows a clear "grant access in Settings" state and
  no task data.
- **R1.2** — all EventKit use is behind the **`ReminderStore` protocol**; the concrete store is
  injected at bootstrap. A `FakeReminderStore` is injected for tests (launch arg), so tests never
  trigger the system prompt.
- **R1.3** — the store **observes `EKEventStoreChanged`** and refreshes the read model when reminders
  change externally (Reminders app, Siri, another device).

### R2 — TaskItem read model · proposal · depends: R1
- **R2.1** — `TaskItem` projects an `EKReminder` + its sidecar row: `id` (externalId), `title`,
  `notes`, `due` (date + hasTime), `isCompleted`, `completionDate`, `priority`, `listId`/`listName`,
  `alarmOffsets`, `isRecurring`, and the joined `rating` / `performanceNotes` / `estimatedDuration` /
  `actualDuration`.
- **R2.2** — the app fetches reminders across the user's chosen lists (default: all reminder lists;
  a Settings option can narrow it), joins the sidecar, and exposes an observable `[TaskItem]`.
- **R2.3** — a `TaskItem` **is rated** iff its sidecar `rating != nil` — the analytics population
  (unchanged from D6.7): placed on the timeline by `completionDate`, else the due date.

### R3 — Performance sidecar & identity · proposal · depends: R1
- **R3.1** — the sidecar stores only `{ rating, performanceNotes, estimatedDuration, actualDuration }`
  keyed by `calendarItemExternalIdentifier`, in a **local SwiftData store** with **per-entry writes**
  (mirrors the old D1). Setting any field upserts one row; clearing all fields may drop it.
- **R3.2** — **orphan reconciliation:** on each sync, sidecar rows whose externalId is absent from
  the store are pruned (a reminder deleted in Apple's app takes its performance data with it). This
  is the crux invariant — unit-tested against the `FakeReminderStore`.
- **R3.3** — externalId is stable per reminder and syncs across devices; a **recurring** reminder
  shares one externalId across occurrences (R8), so its sidecar is per-series, not per-occurrence.

### R4 — Write-back (full CRUD) · proposal · depends: R1, R2
- **R4.1** — Metroneo can **create, edit, complete/uncomplete, and delete** reminders; every write
  goes through the store to EventKit and is committed, so it appears in Apple Reminders and syncs.
- **R4.2** — editable fields write to the `EKReminder`: title, notes, due date (+ time), priority
  (R7), **list** (move via `EKReminder.calendar`), and **alarms** (the early-reminder offset).
  Rating / notes / durations write to the **sidecar** only. A **new** reminder created in Metroneo
  goes into the user's **default Reminders list** (`defaultCalendarForNewReminders`) unless a list is
  chosen — matching the Reminders app.
- **R4.3** — completing in-app sets `isCompleted`/`completionDate` (Apple advances a recurring one);
  the completion flow then offers the rating + actual-time capture (R6). Deleting a reminder also
  prunes its sidecar (R3.2).

### R5 — Lists as grouping · proposal · depends: R1 · *(replaces D5)*
- **R5.1** — **Reminders lists are the collections.** The Tasks tab groups reminders by their list;
  there is no separate Metroneo grouping and **no tags**.
- **R5.2** — Metroneo can **create a list** and **move a reminder between lists** (writes to EventKit).
  List order/color are Apple's; Metroneo just reads them.
- **R5.3** — Metroneo feeds from the user's **default Reminders list** by default
  (`defaultCalendarForNewReminders`); a Settings option can **broaden** the selection to more lists,
  so the app + its analytics scope grows with the user's choice.

### R6 — Completion & the Needs-rating inbox · proposal · depends: R2, R3
- **R6.1** — because a reminder can be completed anywhere, Metroneo surfaces a **Needs rating**
  section in Tasks: reminders that are **completed** and whose sidecar has **no rating**. The
  completed set is read from the Reminders app itself — `predicateForCompletedReminders(withCompletionDateStarting:…)`
  plus the `EKEventStoreChanged` signal (R1.3) — so a completion from Siri/widgets/another device
  appears here.
- **R6.1a** — the **look-back window** (how recently a reminder must have been completed to appear
  in the inbox) is a **user-configurable slider** in Settings (a small set of steps, e.g.
  7 / 14 / 30 / 90 days, default ~14). Any completed reminder can still be rated on demand outside
  the window.
- **R6.2** — rating an item records `rating` (0–100 slider, D11) + optional `performanceNotes` and
  lets the user enter the **actual duration**; it then leaves the inbox and joins the analytics.
- **R6.3** — completing a reminder **inside** Metroneo opens the same rating capture immediately
  (optional — rating is skippable, mirroring the old D6.3); externally-completed ones wait in the
  inbox.
- **R6.4** — **estimated** duration is set on the reminder ahead of time (editor, sidecar); **actual**
  is captured at rating time (or when completing in-app).

### R7 — Priority (Apple's buckets) · proposal · depends: R2 · *(replaces the 0–100 priority slider)*
- **R7.1** — priority is Apple's four buckets — **None / Low / Medium / High** — mapped to
  `EKReminder.priority` (0 / 9 / 5 / 1). The editor shows a 4-way picker; there is no 0–100 priority.
- **R7.2** — the 0–100 **`SliderField`** (D11) is retained for the **rating**, which stays 0–100.
- **R7.3 — priority weights the analytics.** The performance **average** (the D16 trend line and the
  "Average" stat) becomes a **weighted mean** of ratings, each rating weighted by its priority
  bucket's weight: `Σ(rating · weight) / Σ(weight)`. Default weights **None = 1, Low = 2, Medium = 3,
  High = 4**, so higher-priority work counts more. The four weights are **configurable in Settings**
  (a new field in the performance-customization prefs, alongside cutoffs / labels / colors / trend —
  D8/D10/D12), each defaulting per above. The **distribution** chart stays raw counts; only the
  average is weighted.

### R8 — Recurrence (aggregate) · proposal · depends: R2
- **R8.1** — recurrence is Apple's (`EKReminder.recurrenceRules`); Metroneo doesn't generate
  occurrences. A recurring reminder shares one externalId, so its performance data is **aggregate**
  across occurrences, not per-occurrence. Editing recurrence is deferred to the Reminders app in v1
  of the companion (read + display the rule; full recurrence editing is a later extension).

### Carried over from `DESIGN.md` — unchanged
These requirements are **unaffected** by the pivot; the population feeding them just changes from
`[Entry]` to `[TaskItem]`. See `DESIGN.md` for their detail.

- **D16 — trend & distribution charts**, **D17 — estimated-vs-actual time bars** — the Performance
  tab is unchanged in shape. Its inputs (`samples`, `durationTotals`) now take `TaskItem`s (rating +
  durations from the sidecar; placement date = `completionDate ?? due`). **One change:** the average
  (trend line + "Average" stat) is now **priority-weighted** per **R7.3** — the sample carries its
  priority weight, and `average` becomes the weighted mean. The distribution counts are unchanged.
- **D8 / D10 / D12 — performance customization** (level cutoffs, labels, **ColorPicker** colors,
  overall-trend thresholds/labels) — unchanged; still local prefs.
- **D11 — slider field** — retained for the rating (see R7.2).
- **D13 — onboarding** — retained but **re-themed**: it now explains the Reminders connection and
  drives the R1.1 access request.

### Removed from `DESIGN.md` — Apple owns these now
- **Events / time blocks** (`scheduled`, all-day, the whole event/task display split) — Reminders
  has no events.
- **D5 collections model** → **Reminders lists** (R5).
- **D9 reminder scheduling** (local notifications, `ReminderScheduler`/`ReminderTiming` fire-date
  math) → **Apple alarms** (`EKAlarm`); Metroneo just sets the offset.
- **D15 recurrence engine** (`Recurrence`/`RecurrenceEngine`/`SeriesService`) → Apple recurrence
  (R8).
- **D18 due-reminder badge** and **D19 overdue red styling** → the Reminders app already badges and
  styles overdue items. *(These were built just before the pivot; they're superseded.)*
- **Calendar tab** / `CalendarGrouping` — removed (no events; Apple has a Scheduled list).
- The **entry store** (`EntryDatabase`, `StoredEntryModels`) and most of `Entry` / `EntryQuery`.

### Tabs (companion)
- **Tasks** — reminders grouped by **list**, plus the **Needs rating** inbox; create/edit/complete/
  delete (R4); tap to edit; the completion filter (open / completed) carries over conceptually.
- **Performance** — unchanged analytics (D16/D17) over rated reminders.
- **Settings** — performance customization (D8/D10/D12), **Reminders access** + **list selection**
  (R5.3), the **Needs-rating look-back** slider (R6.1a), tutorial replay (D13).

---

## Resolved (this round)
- **Default list scope** → the user's Reminders **default list**, broadenable in Settings (R5.3);
  new reminders created in Metroneo go there too (R4.2).
- **Needs-rating window** → a **user-configurable slider** in Settings (R6.1a), reading the
  Reminders app's completion data (R6.1).
- **Recurrence editing** → **read-only** in the companion (R8.1).
- **Sidecar storage** → **SwiftData** (R3.1).
- **Priority in analytics** → **yes** — it weights the performance average (weighted mean), default
  weights 1/2/3/4 for None/Low/Medium/High, **configurable in Settings** (R7.3).

## Still open / deferred
- **Recurrence performance** — aggregate only (R8.1); per-occurrence history is out of scope while
  recurrence is Apple's.

---

## Migration — build order

Phased so the app keeps building throughout; deletions come last.

1. **R1 foundation** ✅ — `ReminderStore` protocol + value types, `EventKitReminderStore`,
   `FakeReminderStore`, Info.plist usage string, access request. *(Additive.)* Tests:
   `ReminderStoreTests`.
2. **R2/R3 read model + sidecar** ✅ — `TaskItem` join, `StoredPerformance` + `PerformanceSidecarStore`
   (SwiftData) with **orphan reconciliation**, and `TaskService` (fetch → reconcile → join →
   items / needsRating / ratedItems). *(Additive; not yet wired into the UI.)* Tests:
   `PerformanceSidecarStoreTests`, `TaskServiceTests` (incl. the reconcile-vs-window edge).
3. **Analytics rewire** ✅ — `PerformanceAnalytics` now has `TaskItem` overloads
   (`samples`/`durationTotals`/`windowedRated`) and the **priority-weighted average** (R7.3):
   `RatedSample` carries a weight, `average` is `Σ(rating·w)/Σ(w)`, and `PriorityWeights` (default
   1/2/3/4) lives in the customization prefs with a **tolerant decode** so upgrades don't wipe prefs.
   The old `[Entry]` path is unchanged (weight 1 = plain mean). *(Analytics are ready; the Performance
   tab is wired to real data when the UI swaps over.)* Tests: weighted average, TaskItem samples/
   trend/durations/windowedRated, priority-weight persistence + legacy decode.
4. **R4 write-back** ✅ — `TaskService` gains create/edit/`setCompleted`/`delete`/`createList`
   (forward to the store) and async rating/estimate/actual (sidecar); every mutation refreshes the
   joined lists, and delete drops the sidecar row. *(Service-level; the editor UI wires to these in
   the next phase.)* Tests: `testCreateEditCompleteRateDelete` (the full lifecycle).
5. **Companion UI** (behind `-COMPANION`, in progress) —
   - ✅ **R6 Needs-rating inbox** + **R5 list grouping** + rating sheet. `CompanionRootView` →
     `ReminderAccessGate` → `CompanionTasksView`: a pinned "Needs rating" inbox over one
     expandable `DisclosureGroup` per Reminders list; the row complete toggle writes back via
     `TaskService.setCompleted`; tapping an inbox item opens `RatingSheet` (rating slider +
     actual-time + notes → `recordRating` → sidecar). Overdue open reminders read red.
     UI tests: `CompanionTasksUITests` (render/expand groups + inbox, rate-from-inbox);
     complete→write-back→inbox is covered at the service level (`testCreateEditCompleteRateDelete`).
   - ✅ **R4 Editor** — `CompanionReminderEditor` creates/edits a reminder (title/notes/due +
     `hasDueTime`, 4-way **R7 priority** segmented picker, list picker, early-reminder alarm →
     EventKit) with estimated duration → sidecar; delete + read-only recurrence note. Reached via
     an Add button and tap-to-edit on a row. UI tests: create-appears-in-default-list,
     tap-row-opens-prefilled-editor.
   - ✅ **R2/R7 Performance tab** — `CompanionPerformanceView` renders the same trend / distribution
     / estimated-vs-actual charts off `TaskService.ratedItems`, with the **priority-weighted**
     average (`custom.priorityWeights`). `CompanionRootView` is now a `TabView` (Tasks +
     Performance), both access-gated. UI tests: empty-state render, rate-in-Tasks →
     appears-in-Performance-Recent (end-to-end sidecar → analytics).
   - ✅ **R5.3/R6.1a/R7.3 Settings** — `CompanionSettingsView`: priority-weight steppers (persist via
     customization), a needs-rating window stepper and per-list scope toggles (persist on
     `TaskService` via an injected defaults suite — volatile under `-FAKE-REMINDERS` so tests stay
     deterministic), plus the carried-over Performance customization screen + About. UI tests:
     controls render, list-scope narrows Tasks end-to-end.
   - ⬜ **Onboarding** re-themed for Reminders access (the `ReminderAccessGate` already covers the
     functional grant flow; a themed first-run tutorial is the remaining polish).
6. **Delete** ✅ — the whole `Entry` app is gone and the companion is the default (no `-COMPANION`
   gate). Removed: `Entry`/`EntryCollection`/`Recurrence` models; `EntryService`/`CollectionService`/
   `SeriesService`/`ReminderScheduler`/`CalendarGrouping`/`EntryQuery`/`NotificationRouter` services;
   `EntryDatabase`/`StoredEntryModels` storage; `RootView`/`CalendarView`/`CollectionDetailView`/
   `TaskListView`/`EntryEditorSheet`/`EntrySheet`/`EntryRow`/`CompletionSheet`/`OnboardingView`/
   `PerformanceView`/`SettingsView` views; the `ReminderTiming` scheduling enum (badge/overdue
   math) and the dead `Log` util; plus all Entry-era unit + UI tests. **Kept & repurposed:**
   `ReminderLead` (early-reminder presets, now in `ReminderLead.swift`), `PerformanceAnalytics`
   (Entry overloads stripped — `TaskItem`-only), `PerformanceCustomizationScreen` (extracted from
   `SettingsView` into its own file), `OnboardingGate` (self-contained `seenKey`), and all shared
   perf/color/date utilities. `MetroneoApp` now boots only the companion services. Result: **55
   unit + 8 companion UI tests green**, no `Entry` symbols remain.

### Test plan (sketch)
- **`FakeReminderStore`** seeds reminders/lists in memory → unit + integration tests for the
  **join**, **orphan reconciliation** (R3.2), **write-back** round-trips (R4), the **Needs-rating**
  query (R6.1), and list grouping (R5) — no EventKit, no prompt.
- **Analytics tests carry over** (D16/D17/customization) with `TaskItem` inputs.
- **UI tests** inject the fake store via a launch arg (`-FAKE-REMINDERS`), so flows run without the
  Reminders permission dialog. Companion coverage:

  | Suite | Test | Covers |
  |---|---|---|
  | `CompanionTasksUITests` | renderGroupsAndNeedsRating | R2/R5 list groups, expand, inbox |
  | | rateFromNeedsRatingInbox | R6.2 rating sheet → sidecar |
  | | createReminderAppearsInDefaultList | R4.1 create → write-back → default list |
  | | tapRowOpensPrefilledEditor | R4.2 tap-to-edit, pre-filled |
  | `CompanionPerformanceUITests` | performanceTabRendersEmptyState | R2 charts wiring / empty state |
  | | ratingFeedsPerformance | R2.3 rate → appears in Recent (sidecar → analytics) |
  | `CompanionSettingsUITests` | settingsRendersCompanionControls | R5.3/R6.1a/R7.3 controls render |
  | | listScopeNarrowsTasks | R5.3 scope narrows Tasks + inbox end-to-end |

  Completion write-back (complete → Needs-rating) is covered at the service level
  (`TaskServiceTests.testCreateEditCompleteRateDelete`) — the complete toggle sits inside a
  collapsible `DisclosureGroup` row where XCUITest's nested-button discovery is unreliable.
