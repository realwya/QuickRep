# QuickRep P0-3 Training Note Text Source Model Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a runtime line-based text source model that can be rebuilt from `WorkoutNote.rawText` while preserving stable line identities across local edits.

**Architecture:** Keep `WorkoutNote.rawText` as the only persisted source of truth and derive a `WorkoutTextSnapshot` runtime model from it. The snapshot owns ordered `WorkoutTextLine` values and uses a lightweight reconcile pass to reuse line IDs for unchanged lines after insertion or deletion without promising strong move tracking.

**Tech Stack:** Swift, SwiftData, XCTest

---

### Task 1: Document the P0-3 runtime model

**Files:**
- Create: `docs/plans/2026-03-31-quickrep-p0-3-training-note-text-source-model.md`
- Modify: `docs/plans/2026-03-26-quickrep-training-text-entry-backlog.md`

**Step 1: Write down the approved runtime model**

- Clarify that `rawText` remains the only persisted source of truth.
- Clarify that line IDs are runtime-only anchors for parsing and UI binding.
- Clarify the reconcile rule: unchanged lines keep IDs when possible; inserted lines get new IDs; deleted lines disappear.

**Step 2: Update the backlog item after implementation**

- Mark the two P0-3 checkboxes complete once tests and code are verified.

### Task 2: Add failing tests for the text source model

**Files:**
- Modify: `QuickRepTests/QuickRepTests.swift`

**Step 1: Write the failing tests**

```swift
func testWorkoutNoteBuildsLineBasedTextSnapshotFromRawText()
func testWorkoutNoteReconcilesSnapshotPreservingLineIDsForUnchangedLines()
func testWorkoutNoteReconcilesSnapshotAfterLineDeletion()
```

**Step 2: Run test to verify it fails**

Run: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project QuickRep.xcodeproj -scheme QuickRep -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: FAIL because the snapshot types and helpers do not exist yet.

### Task 3: Implement the runtime text source model

**Files:**
- Create: `QuickRep/Domain/Workout/WorkoutTextSnapshot.swift`
- Modify: `QuickRep/Persistence/WorkoutNote.swift`
- Modify: `QuickRep.xcodeproj/project.pbxproj`

**Step 1: Add the snapshot types**

```swift
struct WorkoutTextLine: Identifiable, Hashable {
    let id: UUID
    let index: Int
    let rawText: String
}

struct WorkoutTextSnapshot: Hashable {
    let lines: [WorkoutTextLine]
    var rawText: String { lines.map(\.rawText).joined(separator: "\n") }
}
```

**Step 2: Add reconcile support**

```swift
static func reconciled(
    rawText: String,
    previous: WorkoutTextSnapshot?
) -> WorkoutTextSnapshot
```

- Split text by newline while preserving blank lines.
- Reuse previous line IDs by matching equal line text left-to-right.
- Assign new IDs to unmatched lines.
- Recompute indices every rebuild.

**Step 3: Add a `WorkoutNote` helper**

```swift
func textSnapshot(reconcilingWith previous: WorkoutTextSnapshot? = nil) -> WorkoutTextSnapshot
```

- This keeps the API centered on the persisted note.
- Do not store the snapshot on the model.

**Step 4: Run the focused tests**

Run: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project QuickRep.xcodeproj -scheme QuickRep -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:QuickRepTests/QuickRepTests`
Expected: PASS for the new P0-3 tests.

### Task 4: Verify scope and update docs

**Files:**
- Modify: `docs/plans/2026-03-26-quickrep-training-text-entry-backlog.md`

**Step 1: Re-check the P0-3 scope**

- Confirm no structured state is persisted outside `rawText`.
- Confirm the implementation stops at runtime line identity and does not start the parser early.

**Step 2: Run the full verification command**

Run: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project QuickRep.xcodeproj -scheme QuickRep -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS with zero test failures.
