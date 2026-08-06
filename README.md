# Metroneo

Metroneo is a **companion to Apple Reminders** — a performance layer over the
tasks you already keep. Built in **Swift + SwiftUI**, it reads and writes your
real reminders through **EventKit** and stores a small **performance sidecar**
(ratings and time tracking) in **SwiftData**, joined to each reminder by its
stable id.

Apple owns the task — title, notes, due date, list, priority, alarms, recurrence,
and completion. Metroneo adds the one thing Apple doesn't: **how well you did.**

## Features

- **Tasks** — your reminders grouped by **list** (an expandable section per list),
  with a pinned **Needs rating** inbox of recently-completed, still-unrated
  reminders. Create, edit, complete, and delete reminders — every change writes
  back to Apple Reminders and syncs. Overdue open reminders read red.
- **Rate after the fact** — finish a reminder anywhere (here, in Reminders, or via
  Siri); it lands in the Needs-rating inbox so you can score it (0–100), add notes,
  and log the **actual time** when you get to it.
- **Performance** — analytics over your **rated** reminders: pick a period, see the
  count and a **priority-weighted** average, a trend line with level cutoffs, a
  distribution, estimated-vs-actual time bars, insights, and a recent list — with
  customizable level labels, colors, and trend thresholds.
- **Priority** — Apple's four buckets (None / Low / Medium / High). Higher-priority
  work counts more toward your average, with weights you configure.
- **Settings** — priority weights, the Needs-rating look-back window, which
  Reminders lists to include, the performance-customization screen, and a replayable
  first-run walkthrough.

See [`DESIGN.md`](DESIGN.md) for the full spec — the numbered requirements
(**R1–R8** for the Reminders integration, **D8–D17** for the performance
experience) and the test plan.

## Requirements

- Xcode 16 or later (Swift 5; Apple frameworks only: SwiftUI, SwiftData, Charts,
  EventKit)
- iOS 17.0+ deployment target (uses `requestFullAccessToReminders`)

## Getting started

```sh
open Metroneo.xcodeproj
```

Select the **Metroneo** scheme and an iOS Simulator (or device), then Run (⌘R). On
first launch Metroneo asks for **full access to Reminders** — grant it to see your
tasks. No third-party dependencies or package resolution required.

### Running the tests

Product ▸ Test (⌘U), or:

```sh
xcodebuild test -scheme Metroneo -destination 'platform=iOS Simulator,name=iPhone 16'
```

- **`MetroneoTests`** — unit + integration coverage of the read model, sidecar,
  services, and the pure analytics (weighted average, trend buckets, durations,
  customization). Reminders access is never touched: an in-memory
  `FakeReminderStore` backs the tests.
- **`MetroneoUITests`** — XCUITest flows launched on the fake store
  (`-FAKE-REMINDERS`): list grouping + Needs-rating, the rating sheet, the reminder
  editor, the Performance tab, Settings (list scope, weights, window), and the
  first-run walkthrough.

Tests cite the DESIGN.md requirement IDs with `// spec: <ID>` comments.

## Architecture

A pure, testable domain + analytics layer sits under the SwiftUI presentation
layer. Two data sources are joined at read time: **Apple Reminders** (via a
`ReminderStore` protocol over EventKit) and a **local SwiftData sidecar**.

```
Metroneo/
├── App/          MetroneoApp (boots the store + sidecar + services)
├── Models/       TaskItem (reminder + sidecar join), PerformanceMetadata
├── Services/     ReminderStore protocol, EventKitReminderStore, FakeReminderStore,
│                 TaskService (fetch → reconcile → join), PerformanceAnalytics,
│                 performance preferences + customization, TrendClassifier,
│                 ReminderLead, OnboardingGate
├── Storage/      StoredPerformance (@Model) + PerformanceSidecarStore (SwiftData)
├── Utilities/    DateTimeUtilities, ColorHex, Palette
└── Views/        CompanionRootView (tabs), ReminderAccessGate, OnboardingView,
                  Tasks (+ editor, rating sheet), Performance, Settings
```

- **`ReminderStore`** wraps EventKit so nothing above it touches `EKEventStore`
  directly. `EventKitReminderStore` backs the app; the in-memory `FakeReminderStore`
  backs tests and previews (injected with `-FAKE-REMINDERS`), so the join / sidecar
  / analytics logic runs without the system store or its permission prompt.
- **`PerformanceSidecarStore`** persists `{ rating, notes, estimated, actual }`
  keyed by the reminder's `calendarItemExternalIdentifier`, with **per-entry writes**
  and **orphan reconciliation** — a reminder deleted in Apple's app takes its
  performance data with it.
- **`TaskService`** is the read/write hub: it fetches reminders, reconciles the
  sidecar against the full live set, joins into `items` / `needsRating` /
  `ratedItems`, and forwards every write to the store or sidecar.
- **Pure logic** (`PerformanceAnalytics`, `TrendClassifier`, `ColorHex`) is
  extracted from the views so it's unit-testable without a running app.

## Data model at a glance

| Type | Owner | Key fields |
| --- | --- | --- |
| `TaskItem` | read model (the join) | id, title, notes, due (+ hasTime), isCompleted, completionDate, priority, listId, alarmOffsets, isRecurring + the sidecar fields |
| Reminder (`EKReminder`) | Apple Reminders | title, notes, due, list, priority, alarms, recurrence, completion |
| `PerformanceMetadata` | Metroneo sidecar | rating, performanceNotes, estimatedDuration, actualDuration |

The sidecar is keyed by the reminder's stable external id; deleting a reminder
prunes its row.

## Project history

Metroneo began as a React Native / Expo app (preserved on the
**`old-expo-react-native`** branch) and was rewritten in native Swift + SwiftUI. It
is now an Apple Reminders companion, focused on performance tracking on top of the
tasks you already keep, as described in [`DESIGN.md`](DESIGN.md).
