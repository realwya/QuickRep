import Foundation
import XCTest
@testable import Gymlog

final class GymlogTests: XCTestCase {
    func testWorkoutNotePersistsRawTextAndDraftProgressSeparately() {
        let updatedAt = Date(timeIntervalSince1970: 123)
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            """,
            updatedAt: updatedAt
        )

        note.draftProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 3)]
        )

        XCTAssertEqual(
            note.rawText,
            """
            @卧推
            20 x 8 x 5
            """
        )
        XCTAssertEqual(note.updatedAt, updatedAt)
        XCTAssertEqual(note.draftProgressState.entries.count, 1)
        XCTAssertEqual(note.draftProgressState.entries[0].completedSets, 3)
    }

    func testWorkoutNoteDraftProgressStateRoundTripsThroughEncodedData() throws {
        let note = WorkoutNote(rawText: "@卧推\n20 x 8 x 5")
        let expectedState = WorkoutDraftProgressState(
            entries: [
                WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 2),
                WorkoutDraftProgressEntry(lineIndex: 3, completedSets: 1),
            ]
        )

        note.draftProgressState = expectedState

        let restoredNote = WorkoutNote(
            rawText: note.rawText,
            draftProgressData: try XCTUnwrap(note.draftProgressData)
        )

        XCTAssertEqual(restoredNote.draftProgressState, expectedState)
    }

    func testExerciseBlockCapturesExerciseRange() {
        let block = ExerciseBlock(
            exerciseName: "卧推",
            startLineIndex: 0,
            endLineIndex: 3
        )

        XCTAssertEqual(block.exerciseName, "卧推")
        XCTAssertEqual(block.startLineIndex, 0)
        XCTAssertEqual(block.endLineIndex, 3)
    }

    func testBuiltinExerciseLibraryEntriesAreMarkedBuiltin() {
        let entries = ExerciseLibraryCatalog.builtinEntries()

        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.isBuiltin })
        XCTAssertTrue(entries.contains { $0.name == "卧推" })
    }

    func testWorkoutNoteBuildsLineBasedTextSnapshotFromRawText() {
        let rawText = """
        @卧推
        20 x 8 x 5

        最后两组感觉很重
        """
        let note = WorkoutNote(rawText: rawText)

        let snapshot = note.textSnapshot()

        XCTAssertEqual(
            snapshot.lines.map(\.rawText),
            ["@卧推", "20 x 8 x 5", "", "最后两组感觉很重"]
        )
        XCTAssertEqual(snapshot.lines.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(snapshot.rawText, rawText)
    }

    func testWorkoutNoteReconcilesSnapshotPreservingLineIDsForUnchangedLines() {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )
        let originalSnapshot = note.textSnapshot()

        note.rawText = """
        @卧推
        20 x 8 x 5
        22.5 x 6 x 3
        最后两组感觉很重
        """

        let reconciledSnapshot = note.textSnapshot(reconcilingWith: originalSnapshot)

        XCTAssertEqual(reconciledSnapshot.lines.count, 4)
        XCTAssertEqual(reconciledSnapshot.lines[0].id, originalSnapshot.lines[0].id)
        XCTAssertEqual(reconciledSnapshot.lines[1].id, originalSnapshot.lines[1].id)
        XCTAssertNotEqual(reconciledSnapshot.lines[2].id, originalSnapshot.lines[2].id)
        XCTAssertEqual(reconciledSnapshot.lines[3].id, originalSnapshot.lines[2].id)
    }

    func testWorkoutNoteReconcilesSnapshotAfterLineDeletion() {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            22.5 x 6 x 3
            最后两组感觉很重
            """
        )
        let originalSnapshot = note.textSnapshot()

        note.rawText = """
        @卧推
        22.5 x 6 x 3
        最后两组感觉很重
        """

        let reconciledSnapshot = note.textSnapshot(reconcilingWith: originalSnapshot)

        XCTAssertEqual(reconciledSnapshot.lines.count, 3)
        XCTAssertEqual(reconciledSnapshot.lines[0].id, originalSnapshot.lines[0].id)
        XCTAssertEqual(reconciledSnapshot.lines[1].id, originalSnapshot.lines[2].id)
        XCTAssertEqual(reconciledSnapshot.lines[2].id, originalSnapshot.lines[3].id)
    }

    func testWorkoutNoteCanRebuildSnapshotFromRawTextWithoutCachedDerivedState() {
        let rawText = """
        @卧推
        20 x 8 x 5
        最后两组感觉很重
        """
        let note = WorkoutNote(rawText: rawText)

        let firstSnapshot = note.textSnapshot()
        let rebuiltSnapshot = note.textSnapshot()

        XCTAssertEqual(firstSnapshot.rawText, rawText)
        XCTAssertEqual(rebuiltSnapshot.rawText, rawText)
        XCTAssertEqual(firstSnapshot.lines.map(\.rawText), rebuiltSnapshot.lines.map(\.rawText))
        XCTAssertEqual(firstSnapshot.lines.map(\.index), rebuiltSnapshot.lines.map(\.index))
    }

    func testWorkoutNoteParsesExerciseBlocksPlanLinesAndNoteOwnership() {
        let note = WorkoutNote(
            rawText: """
            今天状态一般
            @卧推
            20 x 8 x 5
            最后两组感觉很重

            @上斜哑铃卧推
            24 x 10 x 4
            """
        )

        let parsedText = note.parsedText()

        XCTAssertEqual(parsedText.exerciseBlocks.map(\.exerciseName), ["卧推", "上斜哑铃卧推"])
        XCTAssertEqual(parsedText.exerciseBlocks.map(\.startLineIndex), [1, 5])
        XCTAssertEqual(parsedText.exerciseBlocks.map(\.endLineIndex), [4, 6])

        XCTAssertEqual(parsedText.planLines.count, 2)
        XCTAssertEqual(parsedText.planLines.map(\.lineIndex), [2, 6])
        XCTAssertEqual(parsedText.planLines[0].exerciseBlockId, parsedText.exerciseBlocks[0].id)
        XCTAssertEqual(parsedText.planLines[0].weight, 20)
        XCTAssertEqual(parsedText.planLines[0].reps, 8)
        XCTAssertEqual(parsedText.planLines[0].targetSets, 5)
        XCTAssertEqual(parsedText.planLines[1].exerciseBlockId, parsedText.exerciseBlocks[1].id)
        XCTAssertEqual(parsedText.planLines[1].targetSets, 4)

        XCTAssertEqual(parsedText.noteLines.map(\.lineIndex), [0, 3, 4])
        XCTAssertNil(parsedText.noteLines[0].exerciseBlockId)
        XCTAssertEqual(parsedText.noteLines[1].exerciseBlockId, parsedText.exerciseBlocks[0].id)
        XCTAssertEqual(parsedText.noteLines[2].exerciseBlockId, parsedText.exerciseBlocks[0].id)
    }

    func testWorkoutNoteTreatsInvalidOrOrphanPlanSyntaxAsNotes() {
        let note = WorkoutNote(
            rawText: """
            20 x 8 x 5
            @卧推
            20 x 8
            20 x 8 x 5 6/5
            20 x 8 x 5 3/4
            0 x 8 x 5
            20 x 8 x 5 0/5
            20 x 8 x 5
            """
        )

        let parsedText = note.parsedText()

        XCTAssertEqual(parsedText.exerciseBlocks.count, 1)
        XCTAssertEqual(parsedText.planLines.count, 1)
        XCTAssertEqual(parsedText.planLines[0].lineIndex, 7)
        XCTAssertEqual(parsedText.planLines[0].targetSets, 5)

        XCTAssertEqual(parsedText.noteLines.map(\.lineIndex), [0, 2, 3, 4, 5, 6])
        XCTAssertNil(parsedText.noteLines[0].exerciseBlockId)
        XCTAssertTrue(parsedText.noteLines.dropFirst().allSatisfy { $0.exerciseBlockId == parsedText.exerciseBlocks[0].id })
    }

    func testWorkoutNoteParsedTextReusesLineIDsWhenReconcilingSnapshot() {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )

        let firstParse = note.parsedText()

        note.rawText = """
        @卧推
        20 x 8 x 5
        22.5 x 6 x 3
        最后两组感觉很重
        """

        let reconciledParse = note.parsedText(reconcilingWith: firstParse.snapshot)

        XCTAssertEqual(reconciledParse.exerciseBlocks[0].id, firstParse.exerciseBlocks[0].id)
        XCTAssertEqual(reconciledParse.planLines[0].id, firstParse.planLines[0].id)
        XCTAssertEqual(reconciledParse.noteLines[0].id, firstParse.noteLines[0].id)
        XCTAssertEqual(reconciledParse.planLines[1].lineIndex, 2)
    }

    func testTrainingEditorTextLayoutBuildsStableLineRangesIncludingTrailingEmptyLine() {
        let lines = TrainingEditorTextLayout.lines(
            in: """
            @卧推

            20 x 8 x 5
            """
        )

        XCTAssertEqual(lines.map(\.index), [0, 1, 2])
        XCTAssertEqual(lines.map(\.text), ["@卧推", "", "20 x 8 x 5"])
        XCTAssertEqual(lines.map(\.contentRange.location), [0, 4, 5])
        XCTAssertEqual(lines.map(\.contentRange.length), [3, 0, 10])
        XCTAssertEqual(lines.map(\.enclosingRange.length), [4, 1, 10])
    }

    func testTrainingEditorTextLayoutResolvesCurrentLineFromCursorLocation() {
        let text = """
        @卧推
        20 x 8 x 5

        """

        XCTAssertEqual(
            TrainingEditorTextLayout.line(containingUTF16Location: 0, in: text).index,
            0
        )
        XCTAssertEqual(
            TrainingEditorTextLayout.line(containingUTF16Location: 4, in: text).index,
            1
        )
        XCTAssertEqual(
            TrainingEditorTextLayout.line(
                containingUTF16Location: (text as NSString).length,
                in: text
            ).index,
            2
        )
    }

    func testTrainingEditorTextLayoutKeepsSelectionOnSameNoteLineWhenPlanLineLengthChanges() {
        let oldText = """
        @卧推
        20 x 8 x 5
        最后两组感觉很重
        """
        let oldLines = TrainingEditorTextLayout.lines(in: oldText)
        let oldSelection = NSRange(
            location: oldLines[2].contentRange.location + 2,
            length: 0
        )

        let newText = """
        @卧推
        22.5 x 6 x 3
        最后两组感觉很重
        """

        let relocatedSelection = TrainingEditorTextLayout.selectionRangePreservingLinePosition(
            from: oldText,
            to: newText,
            selectedRange: oldSelection
        )
        let newLines = TrainingEditorTextLayout.lines(in: newText)

        XCTAssertEqual(
            TrainingEditorTextLayout.line(
                containingUTF16Location: relocatedSelection.location,
                in: newText
            ).index,
            2
        )
        XCTAssertEqual(
            relocatedSelection.location - newLines[2].contentRange.location,
            2
        )
    }

    func testTrainingEditorTextLayoutKeepsSelectionOffsetWhenCurrentPlanLineChangesLength() {
        let oldText = """
        @卧推
        20 x 8 x 5
        """
        let oldLines = TrainingEditorTextLayout.lines(in: oldText)
        let oldSelection = NSRange(
            location: oldLines[1].contentRange.location + 4,
            length: 0
        )

        let newText = """
        @卧推
        22.5 x 8 x 5
        """

        let relocatedSelection = TrainingEditorTextLayout.selectionRangePreservingLinePosition(
            from: oldText,
            to: newText,
            selectedRange: oldSelection
        )
        let newLines = TrainingEditorTextLayout.lines(in: newText)

        XCTAssertEqual(
            TrainingEditorTextLayout.line(
                containingUTF16Location: relocatedSelection.location,
                in: newText
            ).index,
            1
        )
        XCTAssertEqual(
            relocatedSelection.location - newLines[1].contentRange.location,
            4
        )
    }

    func testWorkoutTextProgressUpdaterIncrementsDraftProgressWithoutMutatingText() {
        let parseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )

        let updatedState = WorkoutTextProgressUpdater.incrementProgress(
            for: parseResult.planLines[0].id,
            in: parseResult,
            draftProgress: WorkoutDraftProgressState()
        )

        XCTAssertEqual(parseResult.snapshot.rawText, "@卧推\n20 x 8 x 5")
        XCTAssertEqual(updatedState?.completedSets(forLineIndex: 1), 1)
    }

    func testWorkoutTextProgressUpdaterStopsAfterTargetSets() {
        let parseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let progressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 5)]
        )

        let updatedState = WorkoutTextProgressUpdater.incrementProgress(
            for: parseResult.planLines[0].id,
            in: parseResult,
            draftProgress: progressState
        )

        XCTAssertNil(updatedState)
    }

    func testWorkoutTextProgressUpdaterKeepsProgressWhenEditingNoteLine() {
        let previousParseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )
        let previousProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 3)]
        )

        let reconciledState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            afterEditing: """
            @卧推
            20 x 8 x 5
            最后一组明显变慢
            """,
            previousParseResult: previousParseResult,
            previousDraftProgress: previousProgressState
        )

        XCTAssertEqual(reconciledState.completedSets(forLineIndex: 1), 3)
    }

    func testWorkoutTextProgressUpdaterClearsProgressWhenPlanLineDefinitionChanges() {
        let previousParseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let previousProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 3)]
        )

        let reconciledState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            afterEditing: """
            @卧推
            20 x 8 x 4
            """,
            previousParseResult: previousParseResult,
            previousDraftProgress: previousProgressState
        )

        XCTAssertTrue(reconciledState.isEmpty)
    }

    func testWorkoutTextProgressUpdaterRemovesProgressWhenPlanLineBecomesInvalid() {
        let previousParseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let previousProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 2)]
        )

        let reconciledState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            afterEditing: """
            @卧推
            20 x 8 x
            """,
            previousParseResult: previousParseResult,
            previousDraftProgress: previousProgressState
        )

        XCTAssertTrue(reconciledState.isEmpty)
    }

    func testWorkoutTextProgressUpdaterMigratesProgressWhenPlanLineMovesToNewIndex() {
        let previousParseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )
        let previousProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 2)]
        )

        let reconciledState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            afterEditing: """
            @卧推
            训练前热身完成
            20 x 8 x 5
            最后两组感觉很重
            """,
            previousParseResult: previousParseResult,
            previousDraftProgress: previousProgressState
        )

        XCTAssertNil(reconciledState.completedSets(forLineIndex: 1))
        XCTAssertEqual(reconciledState.completedSets(forLineIndex: 2), 2)
    }

    @MainActor
    func testTrainingEditorSessionRetainsPlanLineAndProgressDuringInvalidIntermediateEdit() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            20 x 8 x 5
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])
        session.handleEditedText(
            """
            @卧推
            20 x 8 x
            """,
            editingLineIndex: 1
        )

        XCTAssertEqual(
            session.noteText,
            """
            @卧推
            20 x 8 x
            """
        )
        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 1), 1)
    }

    @MainActor
    func testTrainingEditorSessionClearsProgressWhenInvalidPlanLineIsCommittedOnLineExit() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            20 x 8 x 5
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])
        session.handleEditedText(
            """
            @卧推
            20 x 8 x
            """,
            editingLineIndex: 1
        )
        session.handleLineExit(from: TrainingEditorTextLayout.lines(in: session.noteText)[1])

        XCTAssertTrue(session.parsedText.planLines.isEmpty)
        XCTAssertTrue(session.draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingEditorSessionClearsProgressWhenCommittedPlanLineDefinitionChanges() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            20 x 8 x 5
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])
        session.handleEditedText(
            """
            @卧推
            20 x 8 x 4
            """,
            editingLineIndex: 1
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 1), 1)

        session.handleLineExit(from: TrainingEditorTextLayout.lines(in: session.noteText)[1])

        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 4"])
        XCTAssertTrue(session.draftProgressState.isEmpty)
    }

    func testWorkoutTextProgressUpdaterFinalizesWorkoutUsingDraftProgress() {
        let parseResult = WorkoutTextParser.parse(
            rawText: """
            @卧推
            20 x 8 x 5
            22.5 x 6 x 3
            25 x 5 x 2
            最后两组感觉很重
            """
        )
        let draftProgressState = WorkoutDraftProgressState(
            entries: [
                WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 4),
                WorkoutDraftProgressEntry(lineIndex: 2, completedSets: 3),
            ]
        )

        let finalizedText = WorkoutTextProgressUpdater.finalizeWorkout(
            in: parseResult,
            draftProgress: draftProgressState
        )

        XCTAssertEqual(
            finalizedText,
            """
            @卧推
            20 x 8 x 4
            22.5 x 6 x 3
            最后两组感觉很重
            """
        )
    }

    @MainActor
    func testTrainingEditorSessionDebouncesTextPersistenceAndSavesLatestState() async {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let session = TrainingEditorSession(
            initialRawText: note.rawText,
            saveDebounceNanoseconds: 50_000_000
        )
        var persistedStates: [TrainingEditorSession.PersistedState] = []

        session.load(from: note, force: true) { _, state in
            persistedStates.append(state)
        }

        session.handleEditedText(
            """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )
        session.handleEditedText(
            """
            @卧推
            22.5 x 6 x 3
            最后两组感觉很重
            """
        )

        XCTAssertTrue(persistedStates.isEmpty)

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(persistedStates.count, 1)
        XCTAssertEqual(
            persistedStates[0].rawText,
            """
            @卧推
            22.5 x 6 x 3
            最后两组感觉很重
            """
        )
        XCTAssertTrue(persistedStates[0].draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingEditorSessionFinishWorkoutCancelsPendingEditPersistenceAndSavesFinalizedText() async {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let session = TrainingEditorSession(
            initialRawText: note.rawText,
            saveDebounceNanoseconds: 200_000_000
        )
        var persistedStates: [TrainingEditorSession.PersistedState] = []

        session.load(from: note, force: true) { _, state in
            persistedStates.append(state)
        }

        session.incrementProgress(for: session.parsedText.planLines[0])
        session.handleEditedText(
            """
            @卧推
            20 x 8 x 5
            最后一组明显变慢
            """
        )
        session.finishWorkout()

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(persistedStates.count, 2)
        XCTAssertEqual(
            persistedStates.last?.rawText,
            """
            @卧推
            20 x 8 x 1
            最后一组明显变慢
            """
        )
        XCTAssertTrue(persistedStates.last?.draftProgressState.isEmpty ?? false)
    }

    @MainActor
    func testTrainingEditorSessionRetainsMemoryStateAndLogsWhenPersistenceFails() {
        let originalLogHandler = GymlogDiagnostics.logHandler
        var logMessages: [String] = []
        GymlogDiagnostics.logHandler = { logMessages.append($0) }
        defer { GymlogDiagnostics.logHandler = originalLogHandler }

        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5
            """
        )
        let session = TrainingEditorSession(
            initialRawText: note.rawText,
            saveDebounceNanoseconds: 1
        )

        session.load(from: note, force: true) { _, _ in
            throw NSError(
                domain: "GymlogTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "save failed"]
            )
        }

        session.handleEditedText(
            """
            @卧推
            22.5 x 6 x 3
            """
        )
        session.flushPendingPersistence()

        XCTAssertEqual(
            session.noteText,
            """
            @卧推
            22.5 x 6 x 3
            """
        )
        XCTAssertEqual(session.parsedText.snapshot.rawText, session.noteText)
        XCTAssertEqual(
            session.lastPersistenceErrorMessage,
            "Failed to persist workout draft: save failed"
        )
        XCTAssertTrue(
            logMessages.contains(where: { $0.contains("Failed to persist workout draft") })
        )
    }

    func testWorkoutNoteLogsAndRecoversWhenDraftProgressDataDecodingFails() {
        let originalLogHandler = GymlogDiagnostics.logHandler
        var logMessages: [String] = []
        GymlogDiagnostics.logHandler = { logMessages.append($0) }
        defer { GymlogDiagnostics.logHandler = originalLogHandler }

        let note = WorkoutNote(
            rawText: "@卧推\n20 x 8 x 5",
            draftProgressData: Data("not-json".utf8)
        )

        XCTAssertTrue(note.draftProgressState.isEmpty)
        XCTAssertTrue(
            logMessages.contains(where: { $0.contains("Failed to decode workout draft progress") })
        )
    }
}
