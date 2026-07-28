# Metroneo — Design Notes

The **target/eventual behavior** of the app, plus the rework **tasks** to get there.
[`FUNCTIONALITY.md`](FUNCTIONALITY.md) is the **current, shipped** behavior. When a design
here ships, fold it into that doc (as new/updated behavior IDs + tests) and check off its
task below.

Three parts:

- **Vision** — how the envisioned next version (v2) works as a whole.
- **Target behavior** — the numbered requirements (**D1–D8**) that get there. Each heading
  carries a **status** (**agreed**/**proposal**) and its **`depends:`** list; its individual
  requirements are sub-numbered **`Dn.m`** (e.g. `D6.5`) for precise citation; the body notes the
  current `FUNCTIONALITY.md` behavior IDs it changes. Build order is in *Dependencies & build
  order* below.
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
  priorityRating: Int                    // plain planning attribute
  recurrence…                            // unchanged from today

  // time (D6 · Option A) — any combination, drives display + calendar placement:
  scheduled: (start, end)?   // + allDay;  "when I'm doing it"  → shows as an EVENT
  deadline:  Date?           // + hasTime; "when it's due"      → shows as a TASK

  // tracking (D6) — on by default, opt out per entry:
  completion: { completedAt: Date? }?                    // present ⇒ checkable
  rating:     { performanceRating, performanceNotes }?   // present ⇒ ratable
}

// D5 — a collection owns its ordered membership; entry ↔ collection is many-to-many.
Collection { id, name, ordering: .ordered | .parallel, memberIds: [EntryId] }
```

- **Display:** `scheduled` ⇒ event; no schedule (deadline-only or undated) ⇒ task.
- **Calendar (grouping follows [ES-05]):** entries are grouped by day; `entries(on: day)`
  returns every entry that lands on that day — by its `scheduled` day **and/or** its `deadline`
  day (so an entry scheduled Tue and due Fri appears on **both**), keyed by local start-of-day —
  and a day with none returns `[]`. Undated entries appear on no day (Tasks list only).
- **Analytics:** entries with a recorded rating.
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
  `shortDate`, `formatDeadline`). Only **[DTU-07]** (`incompleteTasks(_:forDate:)`) is **absorbed**
  by the calendar grouping above — an entry is placed by its own `scheduled`/`deadline` days, so
  no task-specific "due that day" helper is needed.
- **Calendar tab (§6):** UI carries **unchanged in shape** — a day picker driving the per-day
  list, empty state, and an **Add** button — but its **source is the unified entry set** (not
  separate events + incomplete tasks). Rows render event-style or task-style per D6; **Add**
  creates a new entry dated on the selected day; the event + task editors merge into one
  **entry editor** (see below). *Open:* every row is now an entry, so tap-to-edit / swipe can
  apply **uniformly** ([CAL-03]/[CAL-04]) — but note swipe-deleting a due-marker row would delete
  the whole entry, not just remove it from that day; decide edit/delete scope at build time.
- **Entry editor (§6.1 + §7.1 merged):** one editor for every entry, presenting the union of
  today's event + task fields, all with the **same UI as today**:
  - **Title** (D3 client-default), **notes**, **priority** (standalone field).
  - **Schedule** — §6.1 UI unchanged: All-Day toggle + start/end pickers, end-after-start
    validation ([EE-03]), all-day clears times + re-anchoring ([EE-04]).
  - **Deadline** — §7.1 UI unchanged: date + optional-time toggle ([TE-02]/[TE-03]).
  - **Recurrence** (unchanged), **estimated duration**, **types** (D4 chips).
  - **Tracking toggles** (new, D6): completion on/off + rating on/off, both on by default.
  - Save preserves id / completedAt / etc. ([TE-04]).
  - **No Performance slider** — rating is set only **after completion** via the rating sheet
    (§7.2); [TE-01]'s editor slider is dropped.
  - **Collection membership** replaces the old **Subtasks** section ([TE-05]): manage it **inline
    in the editor** *and* in a dedicated **collection view** (D5).
- **Tasks tab (§7):** UI carries **similarly**, now sourced from entries — entry cards with a
  complete checkbox (completable entries), tap-to-edit, Edit / Edit-Rating context menu ([TL-07]),
  swipe-delete ([TL-08]), immediate persistence ([TL-09]). Upcoming/Completed becomes a **D7
  filter** ([TL-01]). Subtask-specific parts are **replaced by collections**: completion gating
  ([TL-02]/[TL-03]) is gone (D5), and the subtask checkbox/preview ([TL-05]/[TL-06]) become a
  **collection-membership** indicator on the card, managed in the collection view + editor. The
  **rating sheet (§7.2)** carries unchanged — rate an entry (0–100 + notes) after completion,
  setting its rating aspect ([PR-01]/[PR-02]); level labels display per D8.
- **Performance tab (§8):** the analytics **math is unchanged** ([PA-01]…[PA-11] — ranges,
  bucketing, granularity, trends). What changes: the **population** is now **rated entries** (D6,
  including rated events + former subtasks), the legend/badges use **custom labels** (D8), and a
  rated entry is placed on the timeline by its **`completedAt`, falling back to its own date**
  (`scheduled` / `deadline`) when it was rated without being completed.
- **Settings (§9) & bootstrap (§10):** carry **unchanged** — §9 only gains D8's label editor on
  the Cutoffs screen; §10 keeps its shape (construct store → inject → load → show tabs), now
  wiring the unified entry service instead of separate `TaskService` / `EventService`.
- **List order:** default by time (an entry's `scheduled` start, else `deadline`) **ascending**
  (soonest first), with untimed/undated entries at the bottom; configurable via a sort selector (D7).
- **Migration:** today's task → `deadline` + tracking on; event → `scheduled` + tracking off;
  subtask → an entry in a collection.
- **D1–D4 apply here too:** `Entry` uses per-entity persistence (D1), a non-optional UUID `id`
  (D2), a required title (D3), and non-optional `types` (D4) — durable principles that hold for
  `Entry`, not just the current model.

Sections **D5/D6** below detail each piece; **D1–D4** are cross-cutting principles that apply to
both the current model and `Entry`.

---

## Target behavior

### Dependencies & build order

```
D1  D2  D3  D4   →   D5 + D6   →   D7
(foundational,       (v2 core         (needs the
 independent)         model —          Entry model)
                      build together)

D8  — independent (preferences + display only)
```

- **D1–D4** — foundational and mutually independent; any order, and they apply to the current
  model *and* `Entry`.
- **D5 + D6** — the v2 core model; depend on D1–D4; **design and build together**.
- **D7** — depends on D5 + D6 (needs the `Entry` time model + entry set).
- **D8** — independent of the Entry model; ship anytime.

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
  each.
- **D5.2** — **order lives on the collection (Option B):** an entry's position = its index in
  that collection's `memberIds`; reorder is **one write**. No per-entry `order`. *(Option A — an
  `order` int on the entry — was rejected: an M2M entry needs a different position per collection,
  which one integer can't hold.)*
- **D5.3** — membership is the collection's `memberIds` (single source of truth); "which
  collections is entry X in" is derived, with **no back-reference** on the entry.
- **D5.4** — a collection is a **grouping, not a completable super-entry**: no completion gating.
- **D5.5** — **ordered** collections present the `memberIds` sequence with drag-to-reorder;
  **parallel** collections treat `memberIds` as an unordered set.
- **D5.6** — **deletion:** remove-from-collection drops the id from that collection's `memberIds`
  (entry survives); delete-entry drops it from **every** collection's `memberIds` then deletes it;
  delete-collection removes the grouping only (member entries survive; nothing cascades).
- **D5.7** — *side effect:* former subtasks become first-class entries — a rated one counts in
  analytics ([PA-02]/[PA-06]) and a dated one shows on the Calendar ([DTU-07]); today they're
  invisible to both.

*Removes* §2.3 SubTask, [TS-03]/[TS-09], [TL-02]/[TL-03]/[TL-05]/[TL-06], the subtask parts of
[TE-05]; *adds* a `Collection` model, service ops, and collection/reorder views.

### D6 — One `Entry` type; completion & rating are independent per-item capabilities · proposal · depends: D1–D4 (co-designed with D5)
The Task/Event split is replaced by a single **`Entry`**.

- **D6.1** — one `Entry` replaces `Task`, `SubTask`, and `Event`.
- **D6.2** — **completion** and **rating** are independent **optional aspects** (composition, not
  a fat struct): `completion: Completion?` (⇒ checkable; holds `completedAt`) and
  `rating: Rating?` (⇒ ratable; holds `performanceRating`, `performanceNotes`). An entry may have
  neither / either / both — no dead fields. `priorityRating` is a **plain `Entry` field**.
- **D6.3** — `isCompletable = completion != nil`; `isCompleted = completion?.completedAt != nil`;
  `isRatable = rating != nil`. Completing does **not** force a rating (separate action).
- **D6.4** — tracking is **on by default**: a new entry is completable + ratable; the user opts
  either off per entry *(migration: today's tasks → tracking on, events → tracking off)*.
- **D6.5** — **time model (Option A):** two independent optional attributes —
  `scheduled: (start, end)?` (+ allDay, "when I'm doing it") and `deadline: Date?` (+ hasTime,
  "when it's due"). An entry may have either, both, or neither. **No explicit `date` field** —
  calendar placement is **derived**: scheduled ⇒ block on its day(s); deadline ⇒ due marker;
  both ⇒ both; neither ⇒ off-calendar.
- **D6.6** — **display rule:** a `scheduled` entry shows as an **event**; one without a schedule
  (deadline-only or undated) shows as a **task**.
- **D6.7** — the tabs are **views over one entry set**: Calendar = dated entries; Tasks = the
  working list (task-style + undated), sorted/filtered per **D7**; analytics = entries with a
  recorded rating.
- **D6.8** — **recurrence** stays as today's fields (scope unchanged); **undated** entries are in
  scope (Tasks list only, not the calendar).

*Supersedes* the Task/Event separation; reworks [PA-*], [DTU-07], [TL-*], [EE-*]. **Co-designed
with D5** — the two define the v2 core model.

### D7 — Entry list sorting & filtering · proposal · depends: D5, D6
Entry lists expose a **sort selector**.

- **D7.1** — an entry's **time key** is its `scheduled` start, else its `deadline`; entries with
  neither are **untimed**.
- **D7.2** — **default order:** by time key **ascending** (soonest first), untimed at the bottom.
- **D7.3** — **selectable orders:** time ↑ (default), time ↓, alphabetical (title) — extensible
  (e.g. priority, created).
- **D7.4** — **filtering:** by tracking/completion state (today's Upcoming/Completed becomes one
  filter), tag (`types`), or collection.
- **D7.5** — manual drag-reorder is **not** a global sort — it applies only inside **ordered
  collections** (D5) and overrides the sort there.
- **D7.6** — the store returns entries in any stable order; the **view applies the chosen sort +
  filter**.

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
- **D8.4** — the **Performance Cutoffs** settings screen gains a label field per level (becomes
  "Cutoffs & Labels").

*Extends* [PP-03], [SET-02]/[SET-03], and every level display ([PV-04] legend, badges, recent
list). §4.3's other behaviors — [PP-01], [PP-02], [PP-04], [PP-05], [PP-06] — **carry unchanged**.

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
  `Collection` (ordered `memberIds`, **M2M**, `.ordered`/`.parallel`); migrate `Task`, `SubTask`,
  and `Event` into `Entry`; wire deletion (remove-from-collection drops one `memberIds` id;
  delete-entry drops it from **all**; collection-delete doesn't cascade); make Calendar / Tasks
  tab / analytics views over the entry set (undated entries in the list only); build the
  collection + reorder views. **Ripple:** large — see the v2 model sketch +
  D5/D6. *Sequence after D1 (persistence).*
- [ ] **Build D7 — sorting & filtering.** Add a sort selector to entry lists (default time ↑
  with untimed last; plus time ↓, alphabetical, extensible) and filters (tracking/completion,
  tag, collection); the view applies sort+filter over the entry set. *After D5 + D6.*
- [ ] **Build D8 — customizable level labels.** Store per-level labels in preferences (defaults =
  today's strings); route `text(for:)` and every level display (legend, badges, recent list)
  through them; add label fields to the Performance Cutoffs screen (blank → default). *Independent
  of the v2 model — can ship on either.*
- [ ] **Extract view logic (non-behavioral).** Pull the `(ui — pending extraction)` logic
  (task sort/split, editor `save()`, cutoff validation, end-after-start) into helpers so
  it becomes `(unit)`-testable. No behavior change; moves the "Views" coverage row toward
  covered without an XCUITest target.
