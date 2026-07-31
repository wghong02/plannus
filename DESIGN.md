# Metroneo — Design Notes

The **spec of the app** (the v2 model shipped in this rebuild), plus the rework **tasks** and the
**test plan**. This is now the single source of behavior — the old `FUNCTIONALITY.md` (which
tracked the retired v1 Task/Event model) has been removed; legacy behavior IDs it defined
(`PA-*`, `PV-*`, `TS-*`, …) are cited here only as historical anchors for what a requirement
changed.

Three parts:

- **Vision** — how v2 works as a whole.
- **Target behavior** — the numbered requirements (**D1–D16**) that define it. Each heading
  carries a **status** (**agreed**/**proposal**) and its **`depends:`** list; its individual
  requirements are sub-numbered **`Dn.m`** (e.g. `D6.5`) for precise citation; the body notes the
  legacy behavior IDs it changed. Build order is in *Dependencies & build order* below.
- **Rework tasks** — the concrete steps. *Provisional: we'll confirm the right approach when
  actually working on each refactor.*

---

## Vision — Metroneo v2

*Status: proposal — the destination we're designing toward (D5 + D6).*

Metroneo v2 collapses the task manager and the event calendar into **one planner built on a
single unit: the `Entry`.** There is no hard split between "tasks" and "events" — an entry is
just *a thing you're planning*, and it takes on whatever aspects it needs.

- **Time is flexible.** An entry can be **scheduled** (a time block — "work 2–3pm"), have a
  **deadline** (due-by — "report by Friday"), **both** (time-blocked *and* due), or **neither**
  (a loose to-do). Scheduled entries render as **events** on the calendar; deadline-only and
  undated ones render as **tasks**.
- **Everything is trackable by default — but you choose.** Every new entry can be **completed**
  and **performance-rated** out of the box, and you can switch either off per entry. So a
  calendar event can be rated ("how did that meeting go?"), a quick reminder can be checkable
  but unrated, and a plain marker can be neither. **Performance analytics span anything you've
  rated**, not just tasks.
- **Structure comes from Collections, not nesting.** Instead of a task owning subtasks, entries
  are grouped into **Collections** that are **ordered** (a sequence you can drag to reorder) or
  **parallel** (no order). A collection is a grouping, not a super-task — it never gates
  completion.
- **The tabs are three lenses on one set of entries.** **Calendar** shows dated entries (blocks
  and due markers); **Tasks** shows the working list (including undated entries); **Performance**
  charts your rated entries over time. Same data, three views.

The result: a unified, flexible planner where one `Entry` can be a calendar event, a due-dated
task, a checklist step, or a loose reminder — and performance tracking is a capability you
attach to anything, not a property of one type.

### The v2 core model (`Entry` + `Collection`)
A single **`Entry`** replaces `Task`, `SubTask`, and `Event`; a **`Collection`** groups entries.
Everything below is a per-entry option — an entry uses only the aspects it needs.

```
Entry {
  id, title, notes
  types: [String]                        // D4 — required list; empty = "no tags"
  priorityRating: Int                    // plain planning attribute (0–100)
  createDate: Date                       // default list order + "created" sort (D7.3)
  estimatedDuration: Int?, actualDuration: Int?   // D14 — minutes; both optional
  seriesId: String?, occurrenceIndex: Int?   // D15 — recurrence via a pre-generated Series (RecurrenceRule)

  // time (D6 · Option A) — any combination, drives display + calendar placement:
  scheduled: (start, end)?   // + allDay;  "when I'm doing it"  → shows as an EVENT
  deadline:  Date?           // + hasTime; "when it's due"      → shows as a TASK

  reminder:  Duration?       // D9 — lead time before the time key; DATED entries only

  // tracking (D6) — aspect present ⇒ capability on (on by default; opt out per entry):
  completion: { completedAt: Date? }?                              // present ⇒ checkable; completedAt set ⇒ completed
  rating:     { performanceRating: Int?, performanceNotes: String? }?  // present ⇒ ratable; performanceRating set ⇒ rated
}

// D5 — a collection owns its ordered membership; entry ↔ collection is many-to-many.
Collection { id, name, ordering: .ordered | .parallel, memberIds: [EntryId] }
```

- **Display:** `scheduled` ⇒ event; no schedule (deadline-only or undated) ⇒ task.
- **Calendar (grouping follows [ES-05]):** entries are grouped by day; `entries(on: day)`
  returns every entry that lands on that day, keyed by local start-of-day, and a day with none
  returns `[]`. An entry lands on a day by **either** its `deadline` day **or** any day its
  `scheduled` block spans — a `scheduled` block appears on **every** day from
  `startOfDay(scheduled.start)` through `startOfDay(scheduled.end)` inclusive (a Mon 11pm–Tue 1am
  block shows on **both** Mon and Tue), so an entry scheduled Tue and due Fri appears on both.
  Undated entries appear on no day (Tasks list only). **Completion does not filter placement**
  (unlike today's [DTU-07]): completed dated entries stay on the calendar, rendered distinct and
  ordered **below** the day's incomplete entries; the D7.7 completion filter can hide them.
- **Within-day order:** incomplete rows first, in this sub-order — (1) **timed** `scheduled` blocks
  by start time-of-day, then (2) **all-day** `scheduled`, then (3) **deadline-only** markers
  (by deadline time-of-day, timeless deadlines last) — then **completed** rows below in the same
  sub-order. Ties within a bucket break by title (A→Z) then `id`, mirroring D7.2. *(A given entry
  that is both scheduled and due on the same day shows once, in the scheduled bucket.)*
- **Analytics:** entries with a **recorded rating** — `rating?.performanceRating != nil`. Being
  *ratable* (`rating != nil`, on by default) is **not** enough; a rating is *recorded* only once a
  value is set (via the completion sheet, §7.2, or a later edit). This decouples the analytics
  population from tracking-on-by-default, and lets a rated-but-uncompleted entry count (placed on
  the timeline by its `completedAt`, else its time-key date).
- **Persistence:** one entry store; `upsertEntry` / `deleteEntry` are per-entity (D1), ids are
  unique (D2), titles required (D3), unknown-id delete is a no-op, `deleteEntry` also drops the id
  from every collection's `memberIds` (D5), and every field round-trips — absorbing today's
  §3.1/§3.2. Admin carries too: `reset()` / `stats()` stay **debug-only**, the `inMemory` store
  stays **unit-tests-only**, and open failure throws → fatal (§10).
- **Service mutations:** today's `TaskService` behaviors carry to the entry service — id
  stability ([TS-04]), update-by-id ([TS-05]), delete + unknown-id no-op ([TS-06], now clearing
  the id from `memberIds` rather than cascading subtasks), complete/uncomplete ([TS-07]), rate
  ([TS-08]), and missing-id no-op ([TS-10]). Complete and rate are gated by an entry's
  completion/rating aspects (D6). Only **`toggleSubTask` ([TS-09]) is dropped** — a former
  subtask is just an entry you complete directly.
- **Utilities (§5):** the generic date/time helpers carry **unchanged** — [DTU-01]…[DTU-06]
  (`startOfDay` for day-grouping, `endOfDay` for the no-time deadline default, `combine`, `time`,
  `shortDate`, `formatDeadline`). Only **[DTU-07]** (`incompleteTasks(_:forDate:)`) is **dropped**
  — the calendar grouping above places an entry by its own `scheduled`/`deadline` days (no
  task-specific "due that day" helper), and DTU-07's *incomplete-only* filter is **not** carried
  (completed dated entries stay on the calendar; see Calendar bullet).
- **Calendar tab (§6):** UI carries **unchanged in shape** — a day picker driving the per-day
  list, empty state, and an **Add** button — but its **source is the unified entry set** (not
  separate events + incomplete tasks). Rows render event-style or task-style per D6; **Add**
  creates a new entry dated on the selected day; the event + task editors merge into one
  **entry editor** (see below). Every row is now an entry, so tap-to-edit / swipe apply
  **uniformly** ([CAL-03]/[CAL-04]) — tap opens the entry editor, swipe deletes. Because a
  calendar row is the **whole entry** (deleting a due-marker or block removes the entry from every
  day and every collection, not just that day), **swipe-delete requires a confirmation dialog**
  naming the entry before it deletes. *(Removing an entry from just one day = clearing that
  date/schedule in the editor, a separate action.)*
- **Entry editor (§6.1 + §7.1 merged):** one editor for every entry, presenting the union of
  today's event + task fields, all with the **same UI as today**:
  - **Title** (D3 client-default), **notes**, **priority** (standalone field).
  - **Schedule** — §6.1 UI unchanged: All-Day toggle + start/end pickers, end-after-start
    validation ([EE-03]), all-day clears times + re-anchoring ([EE-04]).
  - **Deadline** — §7.1 UI unchanged: date + optional-time toggle ([TE-02]/[TE-03]).
  - **Recurrence** — the D15 `RecurrenceRule` (frequency × interval + end); setting it on save
    generates the series, and editing an occurrence prompts This / This-and-future / All (D15.6).
  - **estimated duration**, **actual duration** (D14, optional), **types** (D4 chips).
  - **Tracking toggles** (new, D6): completion on/off + rating on/off, both on by default.
  - Save preserves id / completedAt / etc. ([TE-04]).
  - **No priority-style Performance slider on a fresh entry** — for an *incomplete* entry the
    editor has no rating field; a rating is set at completion (completion sheet, §7.2). But a
    **completed** entry's editor **surfaces the completion fields** — `performanceRating` (if
    ratable), `actualDuration`, and an editable **completion date/time** (`completedAt`) — alongside
    the normal edit fields, so a past completion can be adjusted. [TE-01]'s always-on editor slider
    is dropped in favor of this.
  - **Collection membership** replaces the old **Subtasks** section ([TE-05]): manage it **inline
    in the editor** *and* in the collection view — the **By-collection** mode of the Tasks tab (D5).
- **Tasks tab (§7):** the **home for entries *and* collections**, via a segmented toggle between
  **All entries** (the flat working list, sorted/filtered per D7) and **By collection** (entries
  grouped by collection — create/name/reorder collections here; an "Ungrouped" pseudo-group holds
  entries in no collection). The D7.7 filter control applies in both modes. UI otherwise carries
  from today, sourced from entries — entry cards with a complete checkbox (completable entries),
  tap-to-edit, Edit / Edit-Completion context menu ([TL-07], reopening the completion sheet),
  swipe-delete ([TL-08]), immediate persistence ([TL-09]). Upcoming/Completed becomes a **D7
  filter** ([TL-01]). Subtask-specific parts are **replaced by collections**: completion gating
  ([TL-02]/[TL-03]) is gone (D5), and the subtask checkbox/preview ([TL-05]/[TL-06]) become a
  **collection-membership** indicator on the card, managed in the By-collection mode + editor. The
  **completion sheet (§7.2)** (renamed from the rating sheet) is shown on **every** completion.
  It always sets `completedAt = now` and captures **`actualDuration`** — its field pre-filled with
  the entry's `estimatedDuration`, or **blank when `estimatedDuration == nil`** (leaving actual
  `nil` if not entered). If the entry is **ratable** it also shows a **skippable** 0–100 rating +
  notes ([PR-01]/[PR-02]): **skipping leaves `performanceRating = nil`** (completed but not rated ⇒
  absent from analytics); completing never *forces* a rating (D6.3). Level labels display per D8.
- **Performance tab (§8):** the analytics **math is unchanged** ([PA-01]…[PA-11] — ranges,
  bucketing, granularity, trends). What changes: the **population** is now **entries with a
  recorded rating** (`rating?.performanceRating != nil` — D6, including rated events + former
  subtasks), the legend/badges use **custom labels** (D8), and a rated entry is placed on the
  timeline by its **`completedAt`, falling back to its time key** (D7.1: `scheduled.start` else
  `deadline`) when it was rated without being completed. *(The trend renders as two Swift Charts
  plots — a monotone average line with cutoff reference lines + a stacked distribution bar — per
  **D16**.)*
- **Settings (§9) & bootstrap (§10):** carry **unchanged in shape** — §9's single **Performance
  Cutoffs** screen grows into the combined **Performance customization** screen (D8/D10/D12; see
  the consolidated screen note under D12), and §10 keeps its shape (construct store → inject →
  load → show tabs), now wiring the unified entry service instead of separate `TaskService` /
  `EventService`.
- **List order:** default by time (an entry's `scheduled` start, else `deadline`) **ascending**
  (soonest first), with untimed/undated entries at the bottom; configurable via a sort selector (D7).
- **Migration:** **none — dropped.** v2 ships as a fresh entry store; there are no v1 users, so
  the legacy task/event store is not read or converted. *(The default-value rationale in D6.4 —
  a task-like entry tracks, an event-like one doesn't — is design intent, not a data migration.)*
- **D1–D4 apply here too:** `Entry` uses per-entity persistence (D1), a non-optional UUID `id`
  (D2), a required title (D3), and non-optional `types` (D4) — durable principles that hold for
  `Entry`, not just the current model.

Sections **D5/D6** below detail each piece; **D1–D4** are cross-cutting principles that apply to
both the current model and `Entry`.

---

## Target behavior

### Dependencies & build order

```
D1  D2  D3  D4   →   D5 + D6   →   D7, D9, D15
(foundational,       (v2 core         (need the
 independent)         model —          Entry model)
                      build together)

D8, D10, D11, D12, D13, D14  — independent (small / standalone)
```

- **D1–D4** — foundational and mutually independent; any order, and they apply to the current
  model *and* `Entry`.
- **D5 + D6** — the v2 core model; depend on D1–D4; **design and build together**.
- **D7** — depends on D5 + D6 (needs the `Entry` time model + entry set).
- **D9** — depends on D6 (reminders use the `Entry` time model + calendar).
- **D15** — depends on D5 + D6 (recurrence generates `Entry` occurrences; series membership rides
  the collection/persistence work).
- **D8, D10, D11, D12, D13, D14** — independent of the Entry model (small / standalone); ship anytime.

### D1 — Task persistence is per-entity · agreed · depends: —
A mutation writes **only the affected entry**, not the whole set.

- **D1.1** — `upsertEntry(entry)` inserts-or-updates one entry by id and reconciles its
  children/collection membership (added inserted, removed dropped, survivors updated); other
  entries are untouched.
- **D1.2** — `deleteEntry(id)` removes one entry (children/relationships via cascade); an unknown
  id is a no-op.
- **D1.3** — child/relationship removal is always object-by-object / via cascade, **never** a
  batch `delete(model:)` *(invariant — reframes [DB-08])*.
- **D1.4** — the service does single-entity writes with **no whole-set reload**.
- **D1.5** — every mutation updates the observable in-memory state **in place** *and* persists the
  one entity, so the **UI reflects the change immediately** (reactivity via `@Published`/
  Observation; in-memory copy = source of truth for views, store for durability).
- **D1.6** — **cross-service coherence:** when a write's per-entity reconciliation touches a
  *different* service's cache, that cache is updated in place too — never left stale. Concretely,
  `deleteEntry` drops the id from every collection in the store (D5.6); `EntryService` notifies
  the collection cache (`EntryDeletionObserver`, wired at bootstrap §10) to prune the same id in
  memory, so no dangling member id survives and no full reload is needed.

*Supersedes* the whole-set replace ([DB-01]).

### D2 — Non-optional UUID ids, one scheme · agreed · depends: —
- **D2.1** — `Entry` and `Collection` carry a **non-optional `id: String`** defaulting to
  `UUID().uuidString`, assigned at construction — no transient-nil window, no `guard let id` in
  the views.
- **D2.2** — one id scheme: all ids are UUIDs; the legacy `"event-{millis}-{rand}"` format is
  retired.
- **D2.3** — [DB-02] / [TS-01] lose their "mint a UUID when `id == nil`" step — ids exist at
  construction (the add-and-persist behavior itself stays).

*Changes* [DM-04].

### D3 — A title is required (client-defaulted) · agreed · depends: —
Every entry has a non-empty title.

- **D3.1** — the **client generates the default**: the editor fills a blank title with
  `"New Entry"` (a placeholder the user can overwrite).
- **D3.2** — the **store requires a non-empty title** — it rejects empty as a defensive
  guarantee but no longer *coerces* one (defaulting is a client concern).

*Changes* [DB-03]/[TS-02] (coerce → require), [TE-01], the event editor ([EE-01]/[EE-02]).

### D4 — `types` is a non-optional list · agreed · depends: —
- **D4.1** — `Entry.types` is a required `[String]` where **empty means "no tags"** — no `nil`,
  and no nil/empty coercion on save/load/display.

*Changes* [DM-03], §2.1 field type, [DB-06], [TE-04].

### D5 — Entries grouped by Collections (M2M, ordered membership) · proposal · depends: D1, D2
The Task→SubTask nesting is replaced by **flat entries grouped by `Collection`s** — a
flattening, not recursion. (Together with D6, this removes the `SubTask` type entirely.)

```
Collection { id, name, ordering: .ordered | .parallel, memberIds: [EntryId] }
```

- **D5.1** — a `Collection` owns an ordered `memberIds: [EntryId]`; membership is
  **many-to-many** — an entry can belong to several collections, with an independent position in
  each. `memberIds` holds **no duplicates** — adding an already-present id is a no-op (it does not
  append a second copy or change its position), mirroring [TE-05]'s deduped chips. *Example:* entry
  `x` in A at index 2 and B at index 0; reordering A leaves x's index in B unchanged.
- **D5.2** — **order lives on the collection (Option B):** an entry's position = its index in
  that collection's `memberIds`; reorder is **one write**. No per-entry `order`. *(Option A — an
  `order` int on the entry — was rejected: an M2M entry needs a different position per collection,
  which one integer can't hold.)* A drag-reorder persists the **displayed** id sequence (which
  omits any id that resolves to no live entry), so the stored order always matches what the user
  sees — indices are never mapped back onto the raw `memberIds`.
- **D5.3** — membership is the collection's `memberIds` (single source of truth); "which
  collections is entry X in" is derived, with **no back-reference** on the entry.
- **D5.4** — a collection is a **grouping, not a completable super-entry**: no completion gating.
- **D5.5** — **ordered** collections present the `memberIds` sequence with drag-to-reorder;
  **parallel** collections treat `memberIds` as an unordered set and **display members in the
  active D7 sort** (no drag handle). So only ordered collections use `memberIds` order for display;
  for parallel ones `memberIds` is just the membership set. *(Testable: reordering the D7 sort
  reorders a parallel collection's rows but leaves an ordered collection's rows fixed.)*
- **D5.6** — **deletion:** remove-from-collection drops the id from that collection's `memberIds`
  (entry survives); delete-entry drops it from **every** collection's `memberIds` then deletes it —
  in the store *and*, via the deletion observer (D1.6), in the collection cache, so neither can
  keep a dangling member id; delete-collection removes the grouping only (member entries survive;
  nothing cascades).
- **D5.7** — *side effect:* former subtasks become first-class entries — a rated one counts in
  analytics ([PA-02]/[PA-06]) and a dated one shows on the Calendar ([DTU-07]); today they're
  invisible to both.

*Removes* §2.3 SubTask, [TS-03]/[TS-09], [TL-02]/[TL-03]/[TL-05]/[TL-06], the subtask parts of
[TE-05]; *adds* a `Collection` model, service ops, and collection/reorder views.

### D6 — One `Entry` type; completion & rating are independent per-item capabilities · proposal · depends: D1–D4 (co-designed with D5)
The Task/Event split is replaced by a single **`Entry`**.

- **D6.1** — one `Entry` replaces `Task`, `SubTask`, and `Event`.
- **D6.2** — **completion** and **rating** are independent **optional aspects** (composition, not
  a fat struct): `completion: Completion?` (⇒ checkable; holds `completedAt: Date?`) and
  `rating: Rating?` (⇒ ratable; holds `performanceRating: Int?`, `performanceNotes: String?`).
  Both inner values are **optional**: the *aspect's presence* is the capability, and the *inner
  value* is the recorded datum — so an aspect can be present-but-empty (checkable/ratable but not
  yet completed/rated) with no dead fields. An entry may have neither / either / both. `types` is a
  plain required `[String]`; `priorityRating` is a **plain `Entry` field**.
- **D6.3** — `isCompletable = completion != nil`; `isCompleted = completion?.completedAt != nil`;
  `isRatable = rating != nil`; **`isRated = rating?.performanceRating != nil`** (ratable ≠ rated).
  Completing does **not** force a rating (separate action, D6.4). **Gating (defensive):**
  `completeEntry` on a **non-completable** entry, or `rateEntry` on a **non-ratable** entry, is a
  **no-op** — state unchanged, no aspect auto-added (matches [TS-10]'s missing-id no-op). The UI
  also hides the control, but the service guarantees it. *Example:* `completeEntry(id)` on an entry
  with `completion == nil` leaves it uncompleted; `completedAt` stays nil.
- **D6.4** — tracking is **on by default**: a new entry is completable + ratable (both aspects
  present, both inner values nil until acted on); the user opts either off per entry *(migration:
  today's tasks → tracking on, events → tracking off)*. Because *ratable* ≠ *rated* (D6.3), a
  freshly-created entry does **not** yet appear in analytics — it enters the population only once
  `performanceRating` is recorded (via the completion sheet, §7.2, or a later edit).
- **D6.5** — **time model (Option A):** two independent optional attributes —
  `scheduled: (start, end)?` (+ allDay, "when I'm doing it") and `deadline: Date?` (+ hasTime,
  "when it's due"). An entry may have either, both, or neither. **No explicit `date` field** —
  calendar placement is **derived**: scheduled ⇒ block on its day(s); deadline ⇒ due marker;
  both ⇒ both; neither ⇒ off-calendar.
- **D6.6** — **display rule:** a `scheduled` entry shows as an **event**; one without a schedule
  (deadline-only or undated) shows as a **task**.
- **D6.7** — the tabs are **views over one entry set**: Calendar = dated entries (completed shown
  below incomplete, hideable via the D7.7 filter); Tasks = the working list + collections, toggled
  All-entries / By-collection, sorted/filtered per **D7**; analytics = entries with a recorded
  rating (`isRated`, D6.3).
- **D6.8** — **recurrence** is specified by **D15** (a pre-generated `Series` of independent
  entries, replacing today's inert `frequencyPattern`/`frequencyCount`/`recurring` fields);
  **undated** entries are in scope (Tasks list only, not the calendar).
- **D6.9** — **`Entry` init defaults** (the `Entry` analog of [DM-03], for a "new entry" unit
  test): `id = UUID().uuidString` (D2), `title = ""` until the editor defaults it (D3),
  `notes = nil`, `types = []` (D4), `priorityRating = 50`, `createDate = Date()`,
  `estimatedDuration = actualDuration = nil`, `scheduled = deadline = reminder = nil`,
  `seriesId = occurrenceIndex = nil`, and — tracking on by default (D6.4) —
  `completion = Completion(completedAt: nil)`, `rating = Rating(performanceRating: nil,
  performanceNotes: nil)`. So a fresh entry `isCompletable && isRatable` but is neither
  `isCompleted` nor `isRated`.

*Supersedes* the Task/Event separation; reworks [PA-*], [DTU-07], [TL-*], [EE-*]. **Co-designed
with D5** — the two define the v2 core model.

### D7 — Entry list sorting & filtering · proposal · depends: D5, D6
Entry lists expose a **sort selector**.

- **D7.1** — an entry's **time key** is its `scheduled` start, else its `deadline`; entries with
  neither are **untimed**.
- **D7.2** — **default order:** by time key **ascending** (soonest first). **Ties** (equal time
  keys) break by **title, A→Z, case-insensitive**; a further tie breaks by `id` for full stability.
  **Untimed entries always sort to the bottom** — in **both** time ↑ and time ↓ (they have no time,
  so they never flip to the top), themselves title-then-id ordered.
- **D7.3** — **selectable orders:** time ↑ (default), time ↓ (timed entries reversed, untimed still
  last per D7.2), alphabetical by title (A→Z, case-insensitive, id tie-break) — extensible
  (e.g. priority, created).
- **D7.4** — **filtering** by three independent facets: tracking/completion state (today's
  Upcoming/Completed becomes one filter), tag (`types`), and collection. **Selected facets combine
  with AND** — an entry must satisfy every active facet. The completion facet is
  **Upcoming | Completed**; a **non-completable** entry (no `completion` aspect) matches
  **neither**, so it appears only when the completion facet is **off / "All"**. *Example:* filter
  Completed + tag "work" ⇒ only entries that are `isCompleted` **and** carry "work".
- **D7.5** — manual drag-reorder is **not** a global sort — it applies only inside **ordered
  collections** (D5) and overrides the sort there.
- **D7.6** — the store returns entries in any stable order; the **view applies the chosen sort +
  filter**.
- **D7.7** — a **filter control** sits in the **top-left** (leading toolbar) of the **Calendar**,
  **Tasks** (both modes), and **Performance** views, exposing the D7.4 filters (tracking/completion,
  tag, collection). On lists/calendar it narrows what's shown; on the **Performance** tab it narrows
  the **analytics population** (which entries feed the stats/charts).
- **D7.8** — the **sort selector** (D7.3) sits in the **top-right** (trailing toolbar) of the
  **Tasks** tab (both All-entries and By-collection modes) — the two toolbar corners split
  filter (left) / sort (right). *(Calendar and Performance are date-ordered by nature and expose no
  sort selector; a By-collection **ordered** collection's manual drag overrides the sort within it,
  D7.5.)*

*New capability* (no current equivalent).

### D8 — Customizable performance-level labels · agreed · depends: —
Users can **rename** the five performance levels in Settings, alongside the cutoffs.

- **D8.1** — the levels' identity/order and cutoff logic are unchanged; only their **display
  strings** become user-editable (`PerformanceLevel` stays the stable identity).
- **D8.2** — labels are stored in preferences (with the cutoffs, in `UserDefaults`); defaults are
  today's `"Excellent" | "Very Good" | "Good" | "Fair" | "Poor"`.
- **D8.3** — `text(for:)` and every level display (chart legend, badges, insights, recent list)
  resolve through the **custom label**, falling back to the default when a label is blank
  (client-defaulted, like D3).
- **D8.4** — the settings screen gains a **label field per level** (see the consolidated
  "Performance customization" screen note under D12 — the single source for the final screen).

*Extends* [PP-03], [SET-02]/[SET-03], and every level display ([PV-04] legend, badges, recent
list). §4.3's other behaviors — [PP-01], [PP-02], [PP-04], [PP-05], [PP-06] — **carry unchanged**.

### D9 — Reminders & notifications · agreed · depends: D6
A dated entry can carry a reminder that fires a local notification ahead of its time.

- **D9.1** — an entry may carry an optional **reminder** — a lead time *before* its time. The value
  is chosen from a **fixed preset set plus a Custom option**: presets = **At time (0), 5 min, 15 min,
  30 min, 1 h, 2 h, 1 day, 2 days** before; **Custom** accepts an arbitrary duration that must be
  **> 0** (a 0 custom is rejected; "at time" is the 0 preset). Only **dated** entries can have one
  (undated entries have no reference time): the reminder control is available in the editor **only**
  when the entry has a `scheduled` or `deadline`, and clearing all dates clears the reminder.
- **D9.2** — the reference time is the entry's **time key** (D7.1): `scheduled.start` if
  scheduled, else `deadline`. The reminder fires at `reference − leadTime`. *Example:* deadline
  `Fri 17:00`, lead `30 min` ⇒ fires `Fri 16:30`; "at time" ⇒ fires `Fri 17:00`.
- **D9.3** — at that instant the app posts a **local notification** (UserNotifications): **title =
  the entry's `title`**, **body = its formatted time** (the scheduled time or `formatDeadline`
  output, [DTU-06]). Authorization is requested **on first attempt to set a reminder**. A fire-time
  already in the **past is not scheduled** (boundary: a fire time `≤ now` at schedule-time is
  skipped).
- **D9.3a** — **authorization gate:** if permission is **denied**, the reminder control is
  disabled — an entry **cannot** carry a reminder without authorization (no silently-inert
  reminders). Granting later re-enables the control.
- **D9.4** — **tapping the notification opens the app to the Calendar tab scrolled to the entry's
  own time-key day** (D7.1), not necessarily today.
- **D9.5** — *lifecycle:* the notification is (re)scheduled when the reminder changes **or the
  entry's time key changes** (a change to a non-time-key field — e.g. editing `deadline` while a
  `scheduled` still governs the key — does **not** reschedule), and **cancelled** when the entry is
  completed, deleted, or its reminder is removed; **un-completing re-arms** the reminder if its fire
  time is still in the future.

*New capability* (no current equivalent). Needs notification authorization wired at bootstrap
(§10). *(Modeled as a single lead time; a `[Duration]` list — multiple reminders — is a natural
later extension.)*

### D10 — Customizable level colors · agreed · depends: —
Each performance level's fill color is user-editable, alongside its cutoff and label (D8).

- **D10.1** — each level (Excellent → Poor) has a user-editable **fill color**, stored in
  preferences (with the cutoffs + labels).
- **D10.2** — defaults are today's `Palette` colors (green 800 / green 500 / blue 500 / orange
  500 / red 500); each color **persists as a `#RRGGBBAA` hex string** and falls back to the default
  when unset or unparseable (client-defaulted, like D3). *(Round-trip test: store `#1B5E20FF`, read
  it back identically.)*
- **D10.3** — every level-color use resolves through the custom color: the trend line/points,
  distribution bars, cutoff reference lines ([PV-03]/[PV-04]), performance badges, and the legend.
- **D10.5** — **badge/label text color** is chosen automatically **black vs white by whichever has
  the higher WCAG contrast ratio** against the level's fill (per WCAG 2.x relative-luminance +
  contrast formula) — a deterministic, unit-testable pick (e.g. a light yellow fill → black text; a
  dark green → white text).
- **D10.4** — the settings screen gains a **color picker per level** (see the consolidated
  "Performance customization" screen note under D12 — the single source for the final screen).

*Extends* `Palette` (`PerformanceLevel.color` / `color(for:)` become preference-driven), [PV-03]/
[PV-04], and badges; *pairs with* D8 (same screen). Text-contrast is handled by **D10.5** (WCAG
black-or-white pick), replacing today's always-white badge text.

### D11 — Editable slider values · agreed · depends: —
Every 0–100 slider is paired with an **editable number field**, so a value can be dragged *or*
typed.

- **D11.1** — each 0–100 slider shows an editable field bound to the **same value**; dragging the
  slider and typing in the field stay in sync.
- **D11.2** — typed input is **clamped to 0–100** (non-numeric/blank ignored, falling back to the
  current value).
- **D11.3** — applies to the **priority** slider (entry editor) and the **rating** slider (rating
  sheet, §7.2).

*UI detail* — extends the existing slider rows ([TE-01] priority, [PR-01] rating); applies to the
current app and v2 alike.

### D12 — Configurable overall-trend labels & thresholds · agreed · depends: —
The **Overall Trend** insight ([PA-11]) — today hardcoded to Improving / Neutral / Declining at a
±5% band — becomes configurable in both its thresholds and its names. *(This is the trend
classification, distinct from D8's performance-level labels.)*

- **D12.1** — the trend **thresholds** are user-configurable: an improving cutoff (default **+5%**
  relative change) and a declining cutoff (default **−5%**); the band between them reads Neutral.
  The **relative change carries from [PA-11] unchanged**: `(last − first) / first` over the first
  vs last **non-empty** bucket averages — `> improving` ⇒ Improving, `< declining` ⇒ Declining,
  else Neutral; `N/A` when fewer than 2 non-empty buckets; the **zero-first** special case is
  [PA-11]'s (first == 0 ⇒ Improving if last > 0, else Neutral). Only the two cutoffs become
  preference-driven. *Example:* first 60, last 66 ⇒ +10% ⇒ Improving at default +5%, but Neutral if
  the improving cutoff is raised to +15%.
- **D12.2** — the trend **labels** ("Improving" / "Neutral" / "Declining", and "N/A") are
  user-editable strings, defaulting to today's; a blank falls back to the default (client-defaulted,
  like D3/D8).
- **D12.3** — both are stored in preferences (with cutoffs / labels / colors) and applied wherever
  the overall trend is computed/shown ([PA-11], [PV-06]).
- **D12.4** — the settings screen gains fields for the trend thresholds + labels (in the combined
  screen — see the consolidated note below).

*Extends* [PA-11] (threshold + labels become preference-driven) and [PV-06]; pairs with D8/D10
(same preferences area). *New capability.*

> **Consolidated "Performance customization" screen (D8 + D10 + D12).** D8/D10/D12 all edit the
> one settings screen that today is **Performance Cutoffs** ([SET-02]/[SET-03]). The finished
> screen ("**Performance**" under Personal Preferences) has:
> - a **per-level row** (Excellent → Poor), each with its **cutoff** (existing [SET-03] validation:
>   `0…100`, non-decreasing), **label** field (D8, blank → default), and **color** picker (D10,
>   blank → default `Palette`; text-contrast handled per D10.4);
> - an **Overall-Trend** section with the improving/declining **thresholds** (default +5% / −5%)
>   and the three trend **labels** + "N/A" (D12, blank → default);
> - **Reset to Defaults** ([SET-04]) restores cutoffs **and** labels/colors/trend to their
>   defaults.
>
> All of it persists together in `UserDefaults` (cutoffs / labels / colors / trend), and every
> blank-→-default fallback follows the same client-defaulted rule as D3. This paragraph is the
> single source for the screen; D8.4 / D10.4 / D12.4 just add their fields to it.

### D13 — First-run tutorials · agreed · depends: —
A first-time user gets a short guided introduction to the app's features.

- **D13.1** — on **first launch**, show a dismissible **onboarding walkthrough** of the main
  features — the four tabs and core flows (create an entry, set schedule/deadline, complete + rate,
  collections, performance, customization).
- **D13.2** — it is shown **once**: a "seen" flag persists in `UserDefaults`; it's skippable and
  does not reappear after completion/skip.
- **D13.3** — it is **replayable** from Settings (a "Show tutorial" / Help entry).
- **D13.4** — *(optional)* contextual **coach-marks** the first time a feature is opened.

*Standalone* — independent of the model work; its content reflects whatever features have shipped.
*New capability.*

### D14 — Optional estimated + actual duration · agreed · depends: —
An entry can record how long it was estimated to take and how long it actually took — both
optional.

- **D14.1** — an entry carries an optional **estimated duration** and an optional **actual
  duration** (minutes); either, both, or neither.
- **D14.2** — both are editable in the entry editor (`estimatedDuration` already exists; expose
  `actualDuration` too — for a completed entry it appears alongside the other completion fields,
  per the Entry-editor bullet). In v2, `actualDuration` is **also captured on the completion sheet
  (§7.2), shown for every completion**, its field **defaulting to `estimatedDuration`** (the
  planned duration) so the common case is one tap to accept.
- **D14.3** — when both are present, the entry/card shows the **estimate vs actual** (e.g. over/
  under by N min).
- **D14.4** — durations are **planning/display only** — they don't affect scheduling, analytics,
  or completion.

*Surfaces* the existing `estimatedDuration` / `actualDuration` fields (already `Int?` on the
model) — mainly exposes `actualDuration` in the UI. *Small.* *(An "estimation accuracy" insight —
est vs actual over time — is a natural later extension.)*

### D15 — Recurring entries via pre-generated Series · proposal · depends: D5, D6
Recurrence stops being **inert stored fields** (today `frequencyPattern`/`frequencyCount`/
`recurring` never generate anything) and becomes a **finite, pre-generated series of independent
entries**, tracked by a `Series` record.

```
Series { id, rule: RecurrenceRule, template }   // template = the entry fields each occurrence is built from
RecurrenceRule {
  frequency: .daily | .weekly | .monthly | .yearly
  interval:  Int                          // ≥1 — "every {interval} {frequency}"
  end:       .until(Date) | .afterCount(Int)   // NO "never" — a series is always finite
}
// Entry gains:
seriesId:        String?   // provenance: which series this occurrence belongs to (nil ⇒ one-off)
occurrenceIndex: Int?      // 0-based position within the series (the "series number")
```

- **D15.1** — recurrence is a `RecurrenceRule` and **replaces** `frequencyPattern` (incl.
  `custom`), `frequencyCount`, and the `recurring` bool (supersedes D6.8's "fields unchanged"):
  `frequency × interval` = "every N days/weeks/months/years" (`custom` collapses into
  `daily, interval = N`); `recurring` becomes `series membership` (`seriesId != nil`). A rule
  **must** carry an `end` — `.until(date)` or `.afterCount(n)`; **there is no never-ending
  series**, which keeps pre-generation finite and complete.
- **D15.2** — creating a recurring entry **materializes concrete `Entry` occurrences up front**,
  one per rule step from the start through the `end`; each occurrence is a **fully independent
  entry** (own `scheduled`/`deadline`, own `completion`/`rating`, own `reminder`), carrying the
  shared `seriesId` and its `occurrenceIndex`. **Occurrence 0 = the template's own date** (the first
  occurrence is the entry as authored). `.afterCount(n)` requires **`n ≥ 1`** and yields exactly *n*
  occurrences (indices `0…n−1`; `n = 1` is a single, effectively non-recurring occurrence);
  `.until(d)` yields every occurrence whose date `≤ d` (a boundary occurrence exactly on `d` is
  included), and is empty-guarded so `d` before the start yields just occurrence 0.
- **D15.3** — occurrence *k* offsets the template's `scheduled`/`deadline` by
  `k × interval × frequency-unit` (weekly interval 2 → +0, +14, +28 days). Both time keys shift
  together, preserving time-of-day. **Month/year day-of-month clamping follows RFC 5545:** the
  original day-of-month is the **anchor**, and each occurrence clamps to that month's last valid day
  **without drifting** — monthly from **Jan 31** ⇒ Feb 28 (29 in a leap year), **Mar 31**, Apr 30,
  **May 31**… (March returns to 31; it does not stay at 28). Yearly on **Feb 29** ⇒ Feb 28 in
  non-leap years, Feb 29 in leap years.
- **D15.4** — **each occurrence tracks independently** (D6): it completes and rates on its own
  date, so a recurring entry yields a **per-occurrence performance time series** in analytics
  ([PA-*]) — the point of D6.4. There is **no** series-level completion/rating roll-up.
- **D15.5** — occurrences are **ordinary entries** — they appear on their own calendar days (D6
  rules) and in the Tasks list like any entry; a row/card may show a recurrence indicator +
  `occurrenceIndex` (e.g. "3 of 10").
- **D15.6** — **edit/delete scope** (Apple-Calendar style): acting on one occurrence prompts
  **This / This-and-future / All-in-series**. *This* **detaches** the occurrence (clears
  `seriesId`/`occurrenceIndex`) and touches only it; *This-and-future* rewrites the template and
  **regenerates** occurrences from this index forward (earlier occurrences untouched); *All* edits
  the template and regenerates the whole series. **Delete** mirrors the three scopes.
  Because *This-and-future* and *All* delete the edited occurrence and regenerate it under a fresh
  id, `edit(_:scope:)` **returns the surviving occurrence's id** (the same-index regenerated one, or
  the new series' occurrence 0), and the editor re-attaches collection membership to *that* id — so
  membership follows the occurrence across a regenerate instead of stranding on the deleted id.
- **D15.7** — **reminders (D9)** are per occurrence — each generated entry schedules its own off
  its own time key; regenerating (D15.6) re-arms the affected future occurrences and cancels
  removed ones.
- **D15.8** — **persistence:** `Series` is its own per-entity store record (D1); series-scope
  delete removes member entries **object-by-object** (D1.3) then the series row; a series with no
  remaining members is pruned.

*Migration:* n/a — no v1 data is migrated (see the *Migration* note in the Vision). *Supersedes*
D6.8. *New capability.* *(By-weekday / by-monthday refinements
to `RecurrenceRule` are a natural later extension — the shape follows the iCal RFC 5545 subset.)*

### D16 — Performance trend & distribution charts · agreed (shipped) · depends: D6, D8, D10
The Performance tab renders two stacked **Swift Charts** plots over the existing trend series
([PA-05]…[PA-08]), replacing v2's current placeholder bar-rows. The per-bucket data —
`average`, `taskCount`, and `levelCounts` — already exists on `PerformanceDataPoint`, so this is a
**rendering layer**, not new analytics.

- **D16.1 — Top plot (average line):** a `LineMark` of each bucket's `average` vs its period label,
  `.interpolationMethod(.monotone)` (a monotone fit never overshoots, so the line stays within
  0–100), plus a `PointMark` per bucket colored by that average's **level color** (D10). **Empty
  buckets render as a gap** — plot only buckets with `taskCount > 0`, never a drop to 0. Y scale is
  fixed `0…100`.
- **D16.2 — Cutoff reference lines:** a dashed `RuleMark(y:)` at each cutoff (fair / good / veryGood
  / excellent), colored by the level color at ~0.55 opacity (`StrokeStyle(lineWidth: 1.6,
  dash: [5, 3])`).
- **D16.3 — Bottom plot (distribution):** a **stacked `BarMark`** per bucket — one segment per
  `PerformanceLevel` sized by that bucket's `levelCounts`, colored by the level color (D10); Y = task
  count. Shares the top plot's X scale.
- **D16.4 — Shared category legend** (Excellent → Poor) beneath the plots, using the **custom labels
  (D8) + custom colors (D10)**.
- **D16.5 — Interaction:** `.chartXSelection` on the top plot drops a `RuleMark(x:)` at the selected
  bucket with a callout annotation (period · avg · task count) — tap/drag to inspect. The callout
  appears **only over a bucket that has data** (`taskCount > 0`); selecting an empty bucket shows
  nothing, so an empty span never reads as a real "avg 0".
- **D16.6 — Axes:** Y axis leading with **fixed-width labels** so both plots' plot areas line up;
  X-axis labels **rotate vertical once there are > 8 buckets**; plot styled with left + bottom edge
  lines and no interior grid.

- **D16.7 — Period-scoped surfaces:** the stat cards, both plots, and the **Recent** list all read
  the **selected period** (Week / Month / 3 Months / Year / All Time / **Custom**, whose start-date
  picker appears only for Custom). The Recent list uses the same window as the stats — so its "in
  this period" copy is honest — and the whole period-derived set (`series`, window samples,
  granularity, recent) is computed **once per render** and threaded into the sub-views, not
  recomputed per accessor.

*Shipped:* `PerformanceView` renders both plots (ported from the pre-rebuild chart view,
`git show 881a5d6:Metroneo/Views/PerformanceView.swift`) onto the entry / `RatedSample` series with
the custom labels/colors; chart rendering is covered by `UITEST-6.2` and the Custom-period picker by
`UITEST-6.3`. *(Was `[PV-03]`/`[PV-04]`/`[PV-06]` in the retired FUNCTIONALITY.md.)*

---

## Rework tasks

*Provisional — confirm the approach when working on each refactor.*

- [ ] **Build D1 — per-entity upsert.** Add `upsertTask` (with subtask/collection
  reconciliation) + `deleteTask(id:)`; make `taskID` / child id `@Attribute(.unique)`;
  rewire `TaskService` to single-task writes; drop the whole-set reload. **Ripple:** retire
  [DB-01] (*removed*); add DB IDs for upsert/reconcile/delete; reword [DB-08] to the
  object-by-object invariant. *Sequence with D5.*
- [ ] **Build D2 — non-optional ids.** `Task.id`/`SubTask.id` → non-optional `String =
  UUID().uuidString`; retire `Event.makeID`'s timestamp format for UUID; remove the
  `guard let id` unwraps. **Ripple:** [DM-04], [DB-02], [TS-01]. *Pairs with D1.*
- [ ] **Build D3 — title validation.** Placeholders in the editors; disable ✓ on empty;
  relax/drop the coercion. **Ripple:** [DB-03]/[TS-02] (coerce → reject), [TE-01], new
  `[TE-06]` invariant, [EE-01]/[EE-02]; invert `testBlankTitlesDefaultOnSave` /
  `testBlankTitleDefaults`. Decide: unify the event editor too?
- [ ] **Build D4 — `types` non-optional.** `Task.types` → `[String]` default `[]`; drop
  the nil/empty coercion on save/load/editor/display. **Ripple:** [DM-03], [DB-06], [TE-04];
  invert `testEmptyTypesRoundTripToNil`.
- [ ] **Build D5 + D6 — the v2 core model (`Entry` + `Collection`).** One combined effort,
  honoring **D1–D4** on `Entry` (per-entity persistence, non-optional UUID `id`, required
  title, non-optional `types`): introduce `Entry` (optional `scheduled`/`deadline` time per
  Option A + independent `completion`/`rating` aspects, tracking on by default, standalone
  `priorityRating`) and
  `Collection` (ordered `memberIds`, **M2M**, `.ordered`/`.parallel`); **replace** `Task`,
  `SubTask`, and `Event` with `Entry` (delete the old types — no data migration, no v1 users);
  wire deletion (remove-from-collection drops one `memberIds` id;
  delete-entry drops it from **all**; collection-delete doesn't cascade); make Calendar / Tasks
  tab / analytics views over the entry set (undated entries in the list only; calendar shows
  completed-below-incomplete with multi-day `scheduled` spanning all its days); build the Tasks-tab
  **All-entries ⇄ By-collection** toggle (collection browse + drag-reorder for ordered ones) and
  the unified **completion sheet** (actualDuration default = estimated + skippable rating).
  **Ripple:** large — see the v2 model sketch + D5/D6. *Sequence after D1 (persistence).*
- [ ] **Build D7 — sorting & filtering.** Add a sort selector to entry lists (default time ↑
  with untimed last; plus time ↓, alphabetical, extensible) and filters (tracking/completion,
  tag, collection); the view applies sort+filter over the entry set; put a **filter control
  top-left** on the Calendar, collection, and Performance views (on Performance it scopes the
  analytics population). *After D5 + D6.*
- [ ] **Build D8 — customizable level labels.** Store per-level labels in preferences (defaults =
  today's strings); route `text(for:)` and every level display (legend, badges, recent list)
  through them; add label fields to the Performance Cutoffs screen (blank → default). *Independent
  of the v2 model — can ship on either.*
- [ ] **Build D11 — editable slider values.** Pair each 0–100 slider (priority, rating) with an
  editable number field bound to the same value; keep slider ↔ field in sync; clamp typed input to
  0–100. *Small, standalone.*
- [ ] **Build D12 — configurable overall-trend.** Store trend thresholds (default +5% / −5%) +
  labels in preferences; make `overallTrend` ([PA-11]) read them; add fields to the settings
  screen. *Small, standalone.*
- [ ] **Build D13 — first-run tutorials.** First-launch onboarding walkthrough of the tabs + core
  flows; persist a "seen" flag (`UserDefaults`); replayable from Settings; optional contextual
  coach-marks. *Standalone.*
- [ ] **Build D14 — estimated + actual duration.** Expose `actualDuration` in the editor (both
  optional) and on the completion sheet (default = `estimatedDuration`); show estimate-vs-actual
  on the entry/card; keep durations display-only. *Small.*
- [ ] **Build D10 — customizable level colors.** Store a per-level color in preferences (defaults
  = today's `Palette`); make `PerformanceLevel.color` / `color(for:)` preference-driven; add a
  color picker per level to the Cutoffs/Labels screen; handle text-contrast on colored badges.
  *Independent — pairs with D8.*
- [ ] **Build D9 — reminders & notifications.** Add an optional `reminder` lead time to dated
  entries only; schedule/cancel local notifications off the entry's time key (UserNotifications);
  request auth on first reminder-set and **gate the control on grant** (no reminder without auth);
  deep-link the notification tap to the Calendar tab at the **entry's own date**; cancel on
  complete/delete/reschedule and **re-arm on un-complete** if still future. *Depends on D6.*
- [ ] **Build D15 — recurring entries via Series.** Add `RecurrenceRule` (frequency × interval +
  `end` = until/after-N, no "never") and a per-entity `Series` record; give `Entry` `seriesId` +
  `occurrenceIndex`; **pre-generate** independent occurrences on save (each with own dates /
  tracking / reminder); wire the **This / This-and-future / All** edit+delete prompt with
  regeneration; retire `frequencyPattern`/`frequencyCount`/`recurring`/`custom`. **Ripple:** D6.8
  (*superseded*), the model sketch, D9 (per-occurrence reminders). *After D5 + D6.*
- [ ] **Extract view logic (non-behavioral).** Pull the `(ui — pending extraction)` logic
  (task sort/split, editor `save()`, cutoff validation, end-after-start) into helpers so
  it becomes `(unit)`-testable. No behavior change; moves the "Views" coverage row toward
  covered without an XCUITest target.

---

## Appendix — v2 test plan

The tests for each **D-requirement**. The v2 model has **shipped** and most of these rows are
**implemented and passing** (unit/integration under `MetroneoTests`, the `(x)` flows under
`MetroneoUITests`); tests cite their row with a `// spec: <ID>` comment. `D16`'s charts are shipped,
with their rendering covered by the `UITEST-6.2` flow. This appendix is the traceability map between
the spec and the suite.

**Reserved ID prefixes (new):** `ENT` Entry model/aspects · `EGRP` calendar grouping · `EDB`
entry persistence · `ESVC` entry service · `COL` collections · `SORT` sort/filter · `REM`
reminders · `CLR` level colors · `LBL` level labels · `TRND` overall-trend · `SLD` slider fields ·
`TUT` tutorials · `DUR` durations · `SER` series/recurrence. Tags: **(u)** unit · **(i)**
integration (store/`UserDefaults`) · **(v)** view logic — **unit-after-extraction**: the assertion
is pure logic (default/enable predicate, sort/filter application, routing target, regeneration,
reset) that currently lives in a `View`; it becomes **(u)** once pulled into a helper/view-model
per the *Extract view logic* rework task — so v2 keeps XCUITest to a **thin smoke layer**
(a `MetroneoUITests` target covers only what can't be unit-tested — cover dismissal, tab render;
see the *UI smoke* table). Purely cosmetic details (exact toolbar corner, pixel layout) are not
test assertions. This covers **`PREF-UI` and every `(v)` row** below.

### D1 — per-entity persistence
| ID | Tag | Assertion (given → when → then) | Covers |
| --- | --- | --- | --- |
| EDB-01 | i | store `[a,b]` → `upsertEntry(c)` → `loadEntries()==[a,b,c]`; a,b byte-identical | D1.1 |
| EDB-02 | i | store `[a]` → `upsertEntry(a')` (same id, new title) → count 1, title updated in place | D1.1 |
| EDB-03 | i | `deleteEntry(a.id)` removes only a; **unknown id → no-op, no throw** | D1.2 |
| EDB-04 | i | deletes are object-by-object — re-saving over / resetting data holding collections & series never trips a batch `delete(model:)` | D1.3 |
| ESVC-01 | i | any mutation updates the `@Published` in-memory copy **in place** *and* persists one entity; a fresh service on the same store reloads the change (no whole-set reload) | D1.4/D1.5 |

### D2–D4 — foundational, on `Entry`
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| ENT-ID-01 | u | `Entry()`/`Collection()` get a non-optional UUID `id` at construction; two are distinct | D2.1 |
| ENT-ID-02 | u | every id matches UUID format; no `event-{millis}-{rand}` anywhere | D2.2 |
| ENT-ID-03 | i | id captured after insert is unchanged after N later mutations + reloads | D2.1 |
| ENT-TTL-01 | i | store **rejects** empty/whitespace title (`throws .validation`); it does **not** coerce | D3.2 |
| ENT-TTL-02 | v | editor fills a blank title with `"New Entry"` placeholder; ✓ disabled on empty | D3.1 |
| ENT-TYP-01 | u+i | `types` is `[String]` default `[]`; `[]` round-trips as `[]` (**not** nil); no coercion | D4.1 |

### D5 — collections
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| COL-01 | u | `Collection` init: UUID id, ordered `memberIds`, `ordering ∈ {.ordered,.parallel}` | D5 |
| COL-02 | i | M2M: `x` in A@2 and B@0; reordering A leaves x's index in B unchanged | D5.1/D5.2 |
| COL-03 | u | adding an already-present id is a **no-op** — no duplicate, no reposition | D5.1 |
| COL-04 | u | ordered position = index in `memberIds`; reorder rewrites the array in **one write** | D5.2 |
| COL-14 | u | `moveMember` with an out-of-range source/destination is a **no-op** (guarded — `Array.move` would otherwise trap) | D5.2 |
| COL-05 | u | "which collections is X in" is derived from `memberIds`; entry has **no** back-ref | D5.3 |
| COL-06 | u | an incomplete-member collection gates nothing — no completion block | D5.4 |
| COL-07 | u | **ordered** displays `memberIds` order (drag reorders it); **parallel** displays the active D7 sort — changing the sort reorders a parallel collection's rows but **not** an ordered one's | D5.5 |
| COL-08 | i | remove-from-collection drops the id from **that** collection only; entry + other collections keep it | D5.6 |
| COL-09 | i | `deleteEntry(x)` drops x from **every** collection's `memberIds`, then deletes x | D5.6 |
| COL-12 | i | with the deletion observer wired, `deleteEntry(x)` also prunes x from the **collection cache** in place (store + cache agree; no dangling id, no reload) | D1.6/D5.6 |
| COL-13 | i | a drag-reorder persists the **displayed** id order and drops any id that resolves to no live entry (never maps display indices onto raw `memberIds`) | D5.2/D5.5 |
| COL-10 | i | delete-collection removes the grouping only; member entries survive; nothing cascades | D5.6 |
| COL-11 | i | a former-subtask is now a first-class entry — a rated one counts in analytics, and a dated one shows on the calendar | D5.7 |

### D6 — Entry model, aspects, calendar grouping
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| ENT-01 | u | new-entry defaults exactly per **D6.9** (priority 50, types `[]`, both aspects present with nil inner values, dates/series nil) | D6.9 |
| ENT-02 | u | truth table: `completion==nil`→`!isCompletable`; `completion(nil)`→`isCompletable && !isCompleted`; `rating(perf:nil)`→`isRatable && !isRated`; `rating(perf:80)`→`isRated` | D6.3 |
| ENT-03 | u | display rule: a `scheduled` entry → event; deadline-only/undated → task | D6.6 |
| ESVC-02 | i | `completeEntry(id)`→`completedAt=now` (isCompleted); `uncompleteEntry(id)`→nil | D6 |
| ESVC-03 | i | `rateEntry(id,80,notes)`→`performanceRating=80`,notes set; `notes:nil` clears | D6 |
| ESVC-04 | u | **gating no-op**: `completeEntry` on `completion==nil` (or `rateEntry` on `rating==nil`) leaves state unchanged, adds no aspect | D6.3 |
| ESVC-05 | u | any mutation on a missing id → state unchanged, no crash | D6 |
| EGRP-01 | u/i | `entries(on:day)` returns entries landing that day; a day with none → `[]` | D6.5 |
| EGRP-02 | u | multi-day `scheduled` Mon 23:00–Tue 01:00 → returned for **both** Mon and Tue (start-of-day span, inclusive) | D6.5 |
| EGRP-03 | u | scheduled Tue + deadline Fri → appears on **both** Tue and Fri; undated → no day | D6.5 |
| EGRP-04 | u | a **completed** dated entry is still returned (no incomplete-only filter) | D6.7 |
| EGRP-05 | u | within-day order: incomplete [timed-scheduled by start → all-day → deadline-only by time, timeless last] then completed below in same sub-order; ties title→id | Calendar |
| EGRP-06 | u | an entry both scheduled & due the same day appears **once**, in the scheduled bucket | Calendar |

### D7 — sort & filter
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| SORT-01 | u | time key = `scheduled.start` else `deadline`; neither → untimed | D7.1 |
| SORT-02 | u | default time ↑: soonest first; **untimed last**; ties by title A→Z (case-insensitive) then id | D7.2 |
| SORT-03 | u | time ↓: timed reversed, **untimed still last** (don't flip to top) | D7.3 |
| SORT-04 | u | alphabetical: by title case-insensitive, id tie-break | D7.3 |
| SORT-05 | u | drag reorder applies only inside an **ordered** collection and overrides sort there | D7.5 |
| SORT-06 | u | facets combine **AND**: Completed + tag "work" → only `isCompleted` **and** tagged "work" | D7.4 |
| SORT-07 | u | completion facet: a non-completable entry matches **neither** Upcoming nor Completed; appears only when the facet is off | D7.4 |
| SORT-08 | v | filter control top-left on Calendar/Tasks/Performance; sort selector top-right on Tasks; on Performance the filter narrows the analytics population | D7.7/D7.8 |

### D8 / D10 / D12 — performance-customization prefs
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| LBL-01 | u | `text(for:)` returns the custom label; blank → default (rename Excellent→"Crushed it" resolves, "" → "Excellent") | D8.3 |
| LBL-02 | i | labels persist with cutoffs in `UserDefaults`; a fresh service reloads them; reset restores defaults | D8.2 |
| CLR-01 | i | color persists as `#RRGGBBAA` and round-trips (`#1B5E20FF` in == out); blank/unparseable → default | D10.2 |
| CLR-02 | u | defaults equal today's `Palette` (green800/green500/blue500/orange500/red500) | D10.2 |
| CLR-03 | u | badge text = black-vs-white by **higher WCAG contrast** (light-yellow fill→black; dark-green→white) | D10.5 |
| TRND-01 | u | `(last−first)/first` on first/last non-empty buckets; first 60,last 66 → +10% → Improving at +5%, Neutral at +15%; `<2` non-empty → N/A; zero-first per [PA-11] | D12.1 |
| TRND-02 | i | thresholds + trend labels persist in prefs; blank label → default | D12.2/D12.3 |
| PREF-UI | v | one **Performance** screen: per-level cutoff([SET-03] validation)+label+color rows, trend threshold+label section, Reset restores all | D8.4/D10.4/D12.4 |

### D9 — reminders
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| REM-01 | u | reminder settable only on a dated entry; clearing all dates clears the reminder | D9.1 |
| REM-02 | u | value ∈ presets {0,5m,15m,30m,1h,2h,1d,2d} ∪ Custom>0; a custom 0 is rejected | D9.1 |
| REM-03 | u | fire = timeKey − lead: deadline Fri 17:00, lead 30m → Fri 16:30; "at time" → Fri 17:00 | D9.2 |
| REM-04 | i | a fire time `≤ now` at schedule-time is **not** scheduled | D9.3 |
| REM-05 | i | notification title = `entry.title`, body = formatted time ([DTU-06]) | D9.3 |
| REM-06 | i | denied auth → reminder control disabled, **no reminder stored**; grant re-enables | D9.3a |
| REM-07 | v | tapping the notification opens Calendar at the entry's **time-key day** (not today) | D9.4 |
| REM-08 | i | reschedule on **time-key** change only (non-key date change → no reschedule); cancel on complete/delete/remove; **re-arm on un-complete** if still future | D9.5 |

### D11 / D13 / D14 — small standalone
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| SLD-01 | v | slider ↔ number field share one value; dragging updates the field and vice-versa | D11.1 |
| SLD-02 | u | typed input clamped 0–100 (`150`→100, `-5`→0); non-numeric/blank → falls back to current value | D11.2 |
| TUT-01 | u | `OnboardingGate.shouldShow` is true on first launch; `markSeen` persists (not shown again after seen/skip) | D13.1/D13.2 |
| TUT-02 | u | `OnboardingGate.replay` re-arms the walkthrough (Settings "Show Tutorial Again"); the cover dismiss + Skip/Get Started wiring is view-level | D13.3 |
| DUR-01 | u | estimated & actual are independent optionals (either/both/neither) | D14.1 |
| DUR-02 | v | completion sheet's actualDuration field defaults to `estimatedDuration`, **blank when it's nil** (stays nil if untouched) | D14.2 |
| DUR-03 | u | both present → estimate-vs-actual delta (est 30, act 45 → "+15 min") | D14.3 |
| DUR-04 | u | durations affect nothing — scheduling/analytics/completion unchanged when they vary | D14.4 |

### D15 — recurring series
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| SER-01 | u | `RecurrenceRule` = frequency×interval; `custom`→`daily, interval N`; `recurring` ≡ `seriesId != nil` | D15.1 |
| SER-02 | u | a rule **must** carry an `end`; there is no "never" | D15.1 |
| SER-03 | u | generation: occurrence 0 = template date; `afterCount(n≥1)` → n entries, indices `0…n−1` (`n=1` single); `until(d)` → dates `≤ d` inclusive; `d` before start → just occ 0 | D15.2 |
| SER-04 | u | occurrence k offset = `k×interval×unit`; weekly interval 2 → +0,+14,+28 days; time-of-day preserved | D15.3 |
| SER-05 | u | **RFC 5545 month clamp:** Jan 31 monthly → Feb 28 (29 leap), **Mar 31**, Apr 30…; yearly Feb 29 → Feb 28 in non-leap | D15.3 |
| SER-06 | i | occurrences track independently — completing/rating one leaves siblings untouched; each feeds analytics on its own date | D15.4 |
| SER-07 | i | occurrences are ordinary entries — on their own calendar days + in the Tasks list | D15.5 |
| SER-08 | v/i | edit/delete scope: **This** detaches (clears `seriesId`/`occurrenceIndex`, touches only it); **This-and-future** regenerates from this index forward (earlier untouched); **All** edits template + regenerates whole; delete mirrors | D15.6 |
| SER-09 | i | reminders are per occurrence; regeneration re-arms affected future ones, cancels removed | D15.7 |
| SER-10 | i | `Series` is a per-entity record; series-delete removes members object-by-object then the row; an empty series is pruned | D15.8 |
| SER-11 | i | `edit(_:scope:)` returns the **surviving occurrence id** (This → same id; This-and-future → new series' occ 0; All → same-index regenerated) — a live entry, never the deleted one — so membership re-attaches to it | D15.6 |

### UI flows (`MetroneoUITests` — XCUITest)
End-to-end flows that exercise real wiring unit tests can't reach (create → persist → display),
plus the smoke checks for genuinely un-unit-testable UI. Each flow launches with a clean store
(`-UITEST-RESET`) and skips onboarding unless it's the subject; controls carry stable
`accessibilityIdentifier`s (`addButton`, `entryTitleField`, `saveEntryButton`, `completeToggle`).
Tag **(x)** = XCUITest. Grouped **by what they test**, one group per suite file; each suite
subclasses the shared `UITestCase` (launch + navigation helpers). IDs carry a **category** — the
leading number is the suite, the trailing one the test within it (`UITEST-<category>.<n>`) — so
tests on the same UI share a number and stay contiguous. The six categories mirror the
`MetroneoUITests/*.swift` split.

**1 · Launch & navigation** (`SmokeUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-1.1 | x | launch → the four tabs (Calendar/Tasks/Performance/Settings) render and navigate | §1 |

**2 · Onboarding** (`OnboardingUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-2.1 | x | first-run onboarding appears and **Skip dismisses** it to the tabs | D13.1/D13.2 |
| UITEST-2.2 | x | first-run onboarding → paging **Next** through all pages → **Get Started** dismisses it to the tabs | D13.1/D13.2 |

**3 · Entry create & complete** (`EntryFlowUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-3.1 | x | Tasks → **+** → type a title → save → the entry **displays** in the list | §7 / D1.5 |
| UITEST-3.2 | x | complete an entry → the **completion sheet** appears → Done → the entry remains | §7.2 / D6 |

**4 · Collections** (`CollectionUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-4.1 | x | Tasks → By-collection → **+** → name it → Create → the collection displays | D5 |

**5 · Calendar** (`CalendarUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-5.1 | x | Calendar → **+** → save → the entry lands on the selected day (dated by default) | §6 / D6.5 |

**6 · Performance** (`PerformanceUITests`)
| ID | Tag | Assertion | Covers |
| --- | --- | --- | --- |
| UITEST-6.1 | x | Performance tab renders its stat cards (Rated / Average) | §8 |
| UITEST-6.2 | x | with seeded rated data, the Performance **charts** render — trend + distribution sections + the custom-label legend (Excellent…Poor) | D16 |
| UITEST-6.3 | x | Performance → the Custom period reveals the start-date picker (hidden for the other periods) | D16.7 |
