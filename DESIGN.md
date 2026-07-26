# Metroneo — Design Notes

The **target/eventual behavior** of the app, plus the rework **tasks** to get there.
[`FUNCTIONALITY.md`](FUNCTIONALITY.md) is the **current, shipped** behavior. When a design
here ships, fold it into that doc (as new/updated behavior IDs + tests) and check off its
task below.

Two parts:

- **Target behavior** — how things are *meant* to work (the destination). Each entry has a
  **status** — **agreed** (decided) or **proposal** (direction not final) — and notes the
  current `FUNCTIONALITY.md` behavior IDs it changes.
- **Rework tasks** — the concrete steps to get there. *Provisional: we'll confirm the
  right approach when actually working on each refactor.*

---

## Target behavior

### D1 — Task persistence is per-entity · agreed
A task mutation writes **only the affected task**, not the whole set. `upsertTask(task)`
inserts-or-updates one task by id and reconciles its children (added inserted, removed
deleted, survivors updated in place, `order` refreshed); `deleteTask(id)` removes one task
(children via cascade; unknown id is a no-op). Child removal is always object-by-object /
via cascade, **never** a batch `delete(model:)`. `TaskService` does single-task writes with
no whole-set reload. *Supersedes* the whole-set replace ([DB-01]); *reframes* [DB-08] as an
invariant.

### D2 — Non-optional UUID ids, one scheme · agreed
`Task`, its children, and `Event` all carry a **non-optional `id: String`** defaulting to
`UUID().uuidString`, assigned at construction — no transient-nil window, no
`guard let id = task.id` in the views. `Event` ids are UUIDs too; the legacy
`"event-{millis}-{rand}"` format is retired. *Changes* [DM-04], [DB-02], [TS-01].

### D3 — A title is required · agreed
Titles are **validated, not silently defaulted**. The editor shows `"New Task"` /
`"New Subtask"` / `"New Event"` as **placeholder** text; the ✓ save action is disabled while
the title is empty/whitespace, so nothing untitled is created. The store keeps the default
only as a defensive net (or drops it). *Changes* [DB-03]/[TS-02], [TE-01], the event editor
([EE-01]/[EE-02]); adds a "✓ disabled when empty" editor invariant.

### D4 — `types` is a non-optional list · agreed
`Task.types` is a required `[String]` where **empty means "no tags"** — no `nil`, no
nil/empty coercion on save/load/display. *Changes* [DM-03], §2.1 field type, [DB-06],
[TE-04].

### D5 — Tasks grouped by Collections; no subtasks · proposal
The nested Task→SubTask model is replaced by **flat `Task`s grouped by a `Collection`** — a
flattening, not recursion. `Collection { id, name, ordering: .ordered | .parallel }`; `Task`
gains `collectionId: String?` + `order`. A former "subtask" is just a `Task` in a
collection (full task, all features).

- A collection is a **grouping, not a completable super-task**: no completion gating, no
  "can't finish until children done." *(This is the core trade-off — you give up gating
  checklists.)*
- **Ordered** collections show a sequence with a drag-to-reorder view; **parallel** ones
  have none. `order` is display/sequence only (does not gate completion).
- **Side effect:** former subtasks become first-class `Task`s, so they **start counting** in
  the Performance analytics ([PA-02]/[PA-06]) and appear on the Calendar ([DTU-07]) — a
  larger task population, not more logic.
- *Removes* §2.3 SubTask, [TS-03]/[TS-09], [TL-02]/[TL-03]/[TL-05]/[TL-06], the subtask parts
  of [TE-05]; *adds* a `Collection` model, service ops, and collection/reorder views.

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
- [ ] **Build D5 — Task + Collection.** Add `Collection` model + persistence + service;
  add `collectionId`/`order` to `Task`; remove `SubTask` and the cascade; build the
  collection + reorder views. **Open decisions:** (a) `order` is non-gating; (b) deleting a
  collection **orphans** its tasks (`collectionId = nil`), not cascade. **Ripple:** large —
  see D5. *Sequence with D1.*
- [ ] **Extract view logic (non-behavioral).** Pull the `(ui — pending extraction)` logic
  (task sort/split, editor `save()`, cutoff validation, end-after-start) into helpers so
  it becomes `(unit)`-testable. No behavior change; moves the "Views" coverage row toward
  covered without an XCUITest target.
