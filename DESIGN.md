# Metroneo — Design Notes

Metroneo is a **companion to Apple Reminders**. It reads and writes your real
reminders (via EventKit) and layers a **performance-tracking** experience on top:
a rating, performance notes, and estimated-vs-actual time attached to each
reminder, plus analytics over everything you've rated.

Two families of requirements run through this document:

- **`R1…Rn`** — the Reminders integration: access, the read model, the sidecar,
  write-back, lists, the Needs-rating flow, priority, and recurrence.
- **`D8…D17`** — the performance experience: customization, the rating slider,
  durations, and the charts. These are Metroneo's own value on top of a task.

Core decisions: **full read/write companion**; **no events / time blocks**
(Reminders has no event concept); **Apple Reminders lists are the grouping** — no
separate tags; **priority is Apple's four buckets**; **ratings are captured via a
"Needs rating" inbox** (a reminder can be completed anywhere); **no Calendar tab**
(Apple's Reminders already has a date-grouped Scheduled list). New reminders
Metroneo creates go to the user's **default Reminders list**; the **Needs-rating
look-back is a user-configurable window**; **recurrence is read-only**; the
**sidecar is a local SwiftData store**.

---

## Vision — a performance layer over the reminders you already keep

Your tasks live in Apple Reminders — created there, in Metroneo, or by
Siri/widgets, and synced by iCloud across your devices. Metroneo adds the one
thing Apple doesn't: **how well you did.**

- **Apple owns the task; Metroneo owns the performance.** A reminder's title,
  notes, due date, list, priority, alarms, recurrence, and completion are Apple's.
  Metroneo attaches a **rating**, **performance notes**, and an **estimated /
  actual time** to each reminder, stored locally and joined by the reminder's
  stable id.
- **The tasks follow you; the performance data is per-device.** Apple Reminders is
  the source of truth for tasks, so completing a reminder in Siri shows up in
  Metroneo and vice-versa — no task sync, notification scheduling, or recurrence
  engine of Metroneo's own. But the **performance sidecar is a local store** (R3.1):
  the ratings, notes, and durations you record live only on the device that
  recorded them and do **not** currently follow you across devices, even though the
  reminders they attach to do. Cross-device sidecar sync (CloudKit) is a known
  future extension, not a current guarantee.
- **Rate after the fact.** Since a reminder can be finished anywhere, Metroneo
  surfaces a **Needs rating** inbox of recently-completed, still-unrated reminders
  — rate them and log the actual time when you get to it. The analytics span
  everything you've rated.
- **Three surfaces.** **Tasks** is your reminders (grouped by list) plus the
  Needs-rating inbox; **Performance** charts your rated reminders over time;
  **Settings** holds the customization, Reminders access, list scope, and the
  Needs-rating window.

The result: a focused app that turns Apple Reminders into a self-review tool —
trend lines, level distributions, estimated-vs-actual time — without asking anyone
to move their tasks.

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

- **`ReminderStore` protocol** wraps EventKit so nothing above it touches
  `EKEventStore` directly: fetch lists, fetch reminders (matching predicates),
  save / complete / delete a reminder, create a list, and observe external
  changes. A real `EventKitReminderStore` backs the app; a `FakeReminderStore`
  (in-memory) backs the tests, so the join / sidecar / analytics logic is fully
  unit-testable **without** the system store or its permission prompt. The fake is
  injected at launch (`-FAKE-REMINDERS`), the same trick the UI tests use.
- **`PerformanceSidecarStore`** persists the sidecar locally (per-entry writes,
  keyed by externalId) and **reconciles orphans** — sidecar rows whose reminder no
  longer exists are pruned on sync.
- **`TaskItem`** is the value-type projection the UI and analytics consume — an
  `EKReminder`'s relevant fields merged with its sidecar row.

### What Metroneo stores vs. what Apple owns

| Field | Owner | Notes |
| --- | --- | --- |
| title, notes | Apple (`EKReminder.title` / `.notes`) | read/write |
| due date (+ has-time) | Apple (`EKReminder.dueDateComponents`) | read/write; components without time = date-only |
| completion / completionDate | Apple (`EKReminder.isCompleted`) | read/write |
| list membership | Apple (`EKCalendar`) | read/write — create a list, move a reminder |
| early reminder | Apple (`EKReminder.alarms`, `EKAlarm.relativeOffset`) | read/write; a negative offset = "before" |
| recurrence | Apple (`EKReminder.recurrenceRules`) | read-only; aggregate performance (R8) |
| priority | Apple (`EKReminder.priority`) | read/write; four buckets (R7) |
| stable id | Apple (`calendarItemExternalIdentifier`) | the sidecar join key |
| rating, performance notes | **Metroneo sidecar** | local (R3) |
| estimated / actual duration | **Metroneo sidecar** | minutes; local (R3) |

There are no events, time blocks, or tags — Reminders has no event concept, and
lists are the only grouping.

---

## Target behavior — Reminders integration

### R1 — EventKit access · depends: —
- **R1.1** — Metroneo requests **full access to Reminders**
  (`EKEventStore.requestFullAccessToReminders`, iOS 17+) with an
  `NSRemindersFullAccessUsageDescription`. Access is requested during the first-run
  walkthrough (D13) and re-checked on launch; when denied, the app shows a clear
  "grant access in Settings" state and no task data.
- **R1.2** — all EventKit use is behind the **`ReminderStore` protocol**; the
  concrete store is injected at bootstrap. A `FakeReminderStore` is injected for
  tests (launch arg), so tests never trigger the system prompt.
- **R1.3** — the store **observes `EKEventStoreChanged`** and refreshes the read
  model when reminders change externally (Reminders app, Siri, another device).

### R2 — TaskItem read model · depends: R1
- **R2.1** — `TaskItem` projects an `EKReminder` + its sidecar row: `id`
  (externalId), `title`, `notes`, `due` (date + hasTime), `isCompleted`,
  `completionDate`, `priority`, `listId`, `alarmOffsets`, `isRecurring`, and the
  joined `rating` / `performanceNotes` / `estimatedDuration` / `actualDuration`.
- **R2.2** — the app fetches reminders across the user's chosen lists (default: all
  reminder lists; a Settings option can narrow it), joins the sidecar, and exposes
  an observable `[TaskItem]`.
- **R2.3** — a `TaskItem` **is rated** iff its sidecar `rating != nil` — the
  analytics population, placed on the timeline by `completionDate`, else the due
  date.

### R3 — Performance sidecar & identity · depends: R1
- **R3.1** — the sidecar stores only
  `{ rating, performanceNotes, estimatedDuration, actualDuration }` keyed by
  `calendarItemExternalIdentifier`, in a **local SwiftData store** with **per-entry
  writes**. Setting any field upserts one row; clearing all fields drops it.
- **R3.2** — **orphan reconciliation (defensive):** a reminder deleted in Apple's
  app should take its performance data with it, but reconciliation must never
  destroy data for a reminder that still exists. Because a *read* drives a
  *destructive write*, pruning is deliberately conservative:
  - **Full account, not the scoped view.** Reconciliation runs against the **full,
    unscoped** live set (all lists), independent of the Settings list scope (R5.3).
    List scope only filters what the UI *shows*; it never causes deletion. (A scoped
    fetch is a subset, and pruning against a subset was a data-loss bug.)
  - **Empty-guard.** If the live fetch failed or came back empty while the sidecar
    is non-empty (a transient EventKit error, permission loss, or iCloud not yet
    synced), reconciliation is **skipped entirely** — an empty read is treated as
    "unknown", not "everything was deleted".
  - **Grace across syncs.** An id absent from the live set is not pruned on first
    sight; it is marked *pending*, and only dropped once it has been **absent across
    two consecutive successful syncs**. An id that reappears clears its pending mark.
  - **Occurrence snapshots are exempt.** Historical recurring-occurrence rows (R3.3)
    have no live reminder by design and are never pruned by reconciliation.

  This is the crux invariant — unit-tested against the `FakeReminderStore`,
  including that a still-alive but out-of-window rated reminder keeps its data, that
  a scoped view doesn't prune out-of-scope data, and that an empty fetch prunes
  nothing.
- **R3.3** — externalId is stable per reminder. A **recurring** reminder shares one
  externalId across occurrences (Apple advances the same item on completion rather
  than exposing separate occurrence records), so Metroneo gives each occurrence its
  own **composite sidecar identity** — `"<externalId>@<occurrence-due-date>"` — and
  stores one performance row **per occurrence**, not one aggregate row per series.
  - **Capture is at completion time (in-app):** because EventKit does not let us
    re-fetch past occurrences, an occurrence's performance can only be recorded when
    that occurrence is completed. Completing a recurring reminder **inside Metroneo**
    writes an **occurrence snapshot** (the composite id + the occurrence's due date +
    its completion date) before letting Apple advance the series; the snapshot then
    surfaces in the Needs-rating inbox and joins analytics as its own data point.
  - **External completions are best-effort:** a recurring reminder completed in Siri
    / the Reminders app / another device is not delivered as a per-occurrence record;
    Apple simply advances the due date. On refresh (and on the R1.3 change signal)
    Metroneo detects that a known recurring series' due date has **advanced past the
    value it last saw** and synthesizes one occurrence snapshot for the prior
    occurrence. **Caveats:** occurrences completed while the app never ran between
    them are lost, and the completion timestamp is inferred (the prior due date).
  - Occurrence snapshots are historical, sidecar-only records with no live reminder,
    so they are **exempt from orphan reconciliation** (R3.2).

### R4 — Write-back (full CRUD) · depends: R1, R2
- **R4.1** — Metroneo can **create, edit, complete/uncomplete, and delete**
  reminders; every write goes through the store to EventKit and is committed, so it
  appears in Apple Reminders and syncs.
- **R4.2** — editable fields write to the `EKReminder`: title, notes, due date (+
  time), priority (R7), **list** (move via `EKReminder.calendar`), and **alarms**
  (the early-reminder offset). Rating / notes / durations write to the **sidecar**
  only. A **new** reminder goes into the user's **default Reminders list**
  (`defaultCalendarForNewReminders`) unless a list is chosen.
- **R4.3** — completing in-app sets `isCompleted` / `completionDate` (Apple advances
  a recurring one); the completed reminder then surfaces for rating (R6). Deleting a
  reminder also prunes its sidecar (R3.2).

### R5 — Lists as grouping · depends: R1
- **R5.1** — **Reminders lists are the grouping.** The Tasks tab groups reminders
  by their list; there is no separate Metroneo grouping and no tags.
- **R5.2** — Metroneo can **create a list** and **move a reminder between lists**
  (writes to EventKit). List order / color are Apple's; Metroneo just reads them.
- **R5.3** — Metroneo reads all reminder lists by default; a Settings option can
  **narrow the scope** to specific lists, so the app + its analytics focus with the
  user's choice. Scope is stored as: **unset ⇒ all lists** (the default), a **subset
  ⇒ only those**, and an explicit **empty set ⇒ no lists**. Empty is a real,
  persisted state — turning a list off (even the last one, or the only one) sticks
  rather than snapping back to "all"; re-enabling every list collapses back to the
  clean "all" default. With no lists in scope the app simply shows its empty state.

### R6 — Completion & the Needs-rating inbox · depends: R2, R3
- **R6.1** — because a reminder can be completed anywhere, Metroneo surfaces a
  **Needs rating** section in Tasks: reminders that are **completed** and whose
  sidecar has **no rating**. The completed set is read from the Reminders app itself
  (`predicateForCompletedReminders(withCompletionDateStarting:…)`) plus the
  `EKEventStoreChanged` signal (R1.3), so a completion from Siri / widgets / another
  device appears here.
- **R6.1a** — the **look-back window** (how recently a reminder must have been
  completed to appear in the inbox) is a **user-configurable setting** (default ~14
  days). Any completed reminder can still be rated on demand.
- **R6.2** — rating an item records `rating` (0–100 slider, D11) + optional
  `performanceNotes`, the **estimated duration**, and the **actual duration**; it
  then leaves the inbox and joins the analytics. The rating sheet captures the
  estimate too (not only the editor), so a completed reminder — reachable only via
  the sheet — can still get both durations for the D17 bars.
- **R6.3** — completing a reminder inside Metroneo can open the same rating capture;
  externally-completed ones wait in the inbox.
- **R6.4** — **estimated** duration is set ahead of time (editor → sidecar) **or
  adjusted at rating time** (rating sheet → sidecar); **actual** is captured at
  rating time. Capturing both together is what makes the D17 bars populate.
- **R6.5 — Browse completed.** The Needs-rating inbox only surfaces completions
  *inside* the look-back window (R6.1a), so rating something finished earlier needs
  its own surface. Tasks offers a **Browse Completed** view: all completed reminders
  (across the current list scope, newest first), each tappable to open the same
  rating sheet — so "any completed reminder can be rated on demand" is actually
  reachable, not just asserted. Already-rated completions show their level; unrated
  ones invite a rating.

### R7 — Priority (Apple's buckets) · depends: R2
- **R7.1** — priority is Apple's four buckets — **None / Low / Medium / High** — the
  same four the Reminders app itself exposes, mapped to `EKReminder.priority`
  (0 / 9 / 5 / 1). The editor shows a 4-way picker. Apple's underlying field is 1–9;
  Metroneo reads the finer value into a bucket, but to **stay faithful to Apple** an
  edit only rewrites `EKReminder.priority` when the user actually changes the
  bucket — a save that leaves the bucket untouched **preserves Apple's original
  numeric value** (so a reminder at priority 3 isn't silently rewritten to 1).
- **R7.2** — the 0–100 rating slider (D11) is unaffected; priority and rating are
  separate.
- **R7.3 — priority weights the analytics.** The performance **average** (the trend
  line and the "Average" stat) is a **weighted mean** of ratings, each weighted by
  its priority bucket: `Σ(rating · weight) / Σ(weight)`. Default weights
  **None = 1, Low = 2, Medium = 3, High = 4**, so higher-priority work counts more.
  The four weights are **configurable in Settings**, each **≥ 1** (a weight of 0 is
  disallowed — it would silently erase a whole priority bucket from the average and
  can drive the total weight to 0). **Trade-off, by design:** because the headline
  "Average" is *weighted*, it does not equal the plain mean of the ratings a user
  sees in the Recent list, and the **distribution** chart stays *raw counts* — so
  the average and the distribution intentionally answer different questions
  (importance-weighted quality vs. how many landed at each level). The UI labels the
  stat "Average" with this weighting in mind.

### R8 — Recurrence (per-occurrence performance, read-only rule) · depends: R2, R3
- **R8.1** — the recurrence *rule* is Apple's (`EKReminder.recurrenceRules`);
  Metroneo doesn't generate occurrences and the editor shows a read-only note
  (recurrence is edited in the Reminders app). Performance, however, is captured
  **per occurrence** via the composite occurrence identity (R3.3): each completed
  occurrence is its own rated snapshot and its own point on the analytics timeline,
  rather than one aggregate row for the whole series. In-app completions capture the
  occurrence exactly; external completions are best-effort (R3.3).

---

## Target behavior — performance experience

The performance layer is Metroneo's own; it runs off the rated `TaskItem`
population and its settings live in local preferences.

### D8 / D10 / D12 — performance customization
- **Five levels** — Poor / Fair / Good / Very Good / Excellent — are assigned to a
  0–100 rating by four ascending **cutoffs** (fair ≤ good ≤ very-good ≤ excellent),
  validated so they never decrease. Defaults are **Fair 50 / Good 60 / Very Good 75
  / Excellent 90**, spread across the scale so the 0–100 slider's range maps to the
  five levels without the bottom half collapsing into a single "Poor" band.
- Each level's **label (D8)** and **color (D10, a `ColorPicker` with opacity)** are
  user-customizable, with sensible defaults.
- The **overall-trend classification (D12)** compares the first vs. last non-empty
  bucket average; the improving / declining **percent thresholds** and the three
  **trend labels** are configurable.
- All of this is stored in `UserDefaults` via `PerformancePreferencesService`
  (cutoffs) and `PerformanceCustomizationService` (labels, colors, trend, priority
  weights) with a **tolerant decode**, so adding a field never wipes saved prefs.

### D11 — rating slider
- The rating is a **0–100 slider with editable direct numeric input** (`SliderField`),
  reused by the rating sheet and anywhere a 0–100 value is set.

### D14 — estimated + actual duration
- Both durations are optional minute values on the sidecar. **Estimated** is set in
  the editor **or in the rating sheet**; **actual** is captured when rating. Setting
  the estimate in the rating sheet matters because a completed reminder is only
  reachable there — otherwise it could never get an estimate to compare. Together
  they feed the estimated-vs-actual bars (D17).

### D16 — trend & distribution charts
- The Performance tab renders two stacked Swift Charts plots over adaptive time
  buckets (daily → weekly → … → yearly, capped at 12 buckets): a **monotone average
  line** with dashed cutoff reference lines, and a **stacked distribution bar** of
  per-level counts. The average is **priority-weighted** (R7.3); the distribution is
  raw counts. Custom labels and colors (D8/D10) drive both.
- A **period selector** picks the window: **Week / Month / Quarter / Year / All Time
  / Custom** (the 3-month option reads "Quarter"). The selected period sets the
  bucket granularity and scopes the stats, bars, and recent list.

### D17 — estimated vs. actual time bars
- Two bars — total estimated vs. total actual minutes — across the period's
  reminders that recorded **both** durations, shown only when at least one qualifies.

### D13 — first-run walkthrough
- A three-card walkthrough explains the Reminders connection and drives the R1.1
  access request ("Connect Reminders"). Shown once (`OnboardingGate`, a
  UserDefaults flag) and replayable from **Settings → Show Tutorial Again**.

---

## Tabs

- **Tasks** — a pinned **Needs rating** inbox over reminders grouped by **list**
  (each list is a tappable header that expands/collapses its reminders), plus a
  **Browse Completed** entry (R6.5). Each reminder row is a real list row: a
  **leading complete circle** (tap to complete → write-back → Needs-rating, R4.3/R6),
  the **title**, and a **due date + time subtitle** when the reminder has a due date;
  tapping the row (outside the circle) opens the editor. The grouping is a manual
  expand/collapse rather than a `DisclosureGroup`, so each row — and its complete
  circle — is an independent, accessible control. Metroneo does **not** restyle
  overdue reminders (see Non-goals) — the Reminders app already badges and styles
  them, and a date-only reminder due *today* is not overdue until the day ends.
- **Performance** — the trend + distribution charts (D16), estimated-vs-actual bars
  (D17), stat cards, insights, and a recent-rated list, over the rated population
  with the priority-weighted average (R7.3).
- **Settings** — priority weights (R7.3), the Needs-rating window (R6.1a), per-list
  scope (R5.3), the performance customization screen (D8/D10/D12), tutorial replay
  (D13), and About.

---

## Non-goals

- **Events / time blocks** — Reminders has no event concept.
- **Tags** — lists are the only grouping.
- **Local notification scheduling** — Metroneo sets Apple alarms (`EKAlarm`); the
  Reminders app fires them.
- **A recurrence engine** — recurrence is Apple's (R8), read-only.
- **A separate task store, badging, or overdue styling** — the Reminders app is the
  source of truth and already badges / styles overdue items.

---

## Design decisions (resolved)

- **Default list scope** → all reminder lists, narrowable in Settings (R5.3); new
  reminders created in Metroneo go to the user's default list (R4.2).
- **Needs-rating window** → a user-configurable look-back (R6.1a) over the Reminders
  app's completion data (R6.1).
- **Recurrence editing** → read-only (R8.1); per-occurrence history is out of scope
  while recurrence is Apple's.
- **Sidecar storage** → SwiftData (R3.1).
- **Priority in analytics** → weights the performance average (weighted mean),
  default weights 1/2/3/4 for None/Low/Medium/High, configurable in Settings (R7.3).

---

## Implementation — code map

```
Metroneo/
├── App/          MetroneoApp (boots the store + sidecar + services)
├── Models/       TaskItem (the reminder+sidecar join), PerformanceMetadata
├── Services/     ReminderStore protocol, EventKitReminderStore, FakeReminderStore,
│                 TaskService (fetch → reconcile → join), PerformanceAnalytics,
│                 PerformancePreferencesService, PerformanceCustomizationService,
│                 TrendClassifier, ReminderLead, OnboardingGate
├── Storage/      StoredPerformance (@Model) + PerformanceSidecarStore (SwiftData)
├── Utilities/    DateTimeUtilities, ColorHex, Palette
└── Views/        CompanionRootView (tabs), ReminderAccessGate, OnboardingView,
                  CompanionTasksView, BrowseCompletedView, CompanionReminderEditor,
                  RatingSheet, CompanionPerformanceView, CompanionSettingsView,
                  PerformanceCustomizationScreen, SliderField
```

- **`TaskService`** is the read/write hub: `refresh()` fetches the **full, unscoped**
  incomplete + completed set (across all lists), reconciles the sidecar against it
  defensively (R3.2 — scope-independent, empty-guarded, grace across syncs), then
  filters to the Settings list scope (R5.3) *in memory* to build
  `items` / `needsRating` / `ratedItems` and publishes the lists. It subscribes to
  the store's `changes` publisher (R1.3) and refreshes when reminders change
  externally, and detects recurring-series due-date advancement to capture
  best-effort occurrence snapshots (R3.3). Every write forwards to the store or
  sidecar and refreshes.
- **`PerformanceAnalytics`** is pure and operates on `TaskItem`s / `RatedSample`s:
  `samples(from:weights:)`, the weighted `average`, adaptive `trendSeries`,
  `durationTotals`, and `windowedRated`.
- Settings that must persist (needs-rating window, list scope) live on `TaskService`
  backed by an injected `UserDefaults` (a volatile suite under `-FAKE-REMINDERS` so
  UI-test state never leaks across launches).

---

## Test plan

- **`FakeReminderStore`** seeds reminders / lists in memory → unit + integration
  tests for the **join**, **orphan reconciliation** (R3.2), **write-back**
  round-trips (R4), the **Needs-rating** query (R6.1), and list grouping (R5) — no
  EventKit, no prompt.
- **Analytics** — level classification, the priority-**weighted** average,
  `TaskItem` samples / trend / durations / windowedRated, and customization
  persistence + tolerant decode.
- **UI tests** inject the fake store via `-FAKE-REMINDERS` (and skip the walkthrough
  unless `-SHOW-ONBOARDING`), so flows run without the Reminders permission dialog.

  | Suite | Test | Covers |
  |---|---|---|
  | `CompanionTasksUITests` | renderGroupsAndNeedsRating | R2/R5 list groups, expand, inbox |
  | | rateFromNeedsRatingInbox | R6.2 rating sheet → sidecar |
  | | createReminderAppearsInDefaultList | R4.1 create → write-back → default list |
  | | tapRowOpensPrefilledEditor | R4.2 tap-to-edit, pre-filled |
  | | completeCircleMovesReminderToNeedsRating | R4.3/R6 complete circle → write-back → inbox |
  | `CompanionPerformanceUITests` | performanceTabRendersEmptyState | R2 charts wiring / empty state |
  | | ratingFeedsPerformance | R2.3 rate → appears in Recent (sidecar → analytics) |
  | | ratingWithDurationsShowsEstimatedVsActual | D14/D17 rate w/ both durations → bars appear |
  | `CompanionSettingsUITests` | settingsRendersCompanionControls | R5.3/R6.1a/R7.3 controls render |
  | | listScopeNarrowsTasks | R5.3 scope narrows Tasks + inbox end-to-end |
  | | listScopeTogglesEachListOffAndBackOn | R5.3 each/last list toggles off (no revert) + on |
  | `OnboardingUITests` | walkthroughConnectsAndDismisses | D13/R1.1 walkthrough → Connect → Tasks |
  | | onboardingSkippedByDefaultInTests | deterministic skip for other suites |

  The complete circle is directly UI-tested (`completeCircleMovesReminderToNeedsRating`):
  because the list grouping is a manual expand/collapse rather than a `DisclosureGroup`,
  each reminder row — and its leading complete circle — is an independent, accessible
  control that XCUITest can find and tap. The full create → edit → complete → rate →
  delete round-trip also has service-level coverage
  (`TaskServiceTests.testCreateEditCompleteRateDelete`).
