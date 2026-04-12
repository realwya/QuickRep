import Foundation
import SwiftData
import XCTest
@testable import QuickRep

final class QuickRepTests: XCTestCase {
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

    func testTrainingHomeScreenPrimaryWorkoutButtonTitleDefaultsToStartWithoutDraft() {
        XCTAssertEqual(
            TrainingHomeScreen.primaryWorkoutButtonTitle(for: nil),
            "开始训练"
        )
    }

    func testTrainingHomeScreenPrimaryWorkoutButtonTitleDefaultsToStartForEmptyDraftText() {
        XCTAssertEqual(
            TrainingHomeScreen.primaryWorkoutButtonTitle(
                for: WorkoutNote(rawText: " \n\t ")
            ),
            "开始训练"
        )
    }

    func testTrainingHomeScreenPrimaryWorkoutButtonTitleUsesContinueForNonEmptyDraftText() {
        XCTAssertEqual(
            TrainingHomeScreen.primaryWorkoutButtonTitle(
                for: WorkoutNote(rawText: "@卧推\n20 x 8 x 5")
            ),
            "继续训练"
        )
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

    @MainActor
    func testExerciseLibraryStoreSeedsBuiltinEntriesIntoEmptyLibrary() throws {
        let container = try ModelContainer(
            for: ExerciseLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext

        ExerciseLibraryStore.ensureBuiltinEntries(in: modelContext)

        let entries = try modelContext.fetch(FetchDescriptor<ExerciseLibraryEntry>())

        XCTAssertEqual(entries.count, ExerciseLibraryCatalog.builtinExerciseNames.count)
        XCTAssertEqual(
            Set(entries.map(\.name)),
            Set(ExerciseLibraryCatalog.builtinExerciseNames)
        )
        XCTAssertTrue(entries.allSatisfy(\.isBuiltin))
    }

    @MainActor
    func testExerciseLibraryStoreDoesNotDuplicateExistingBuiltinEntries() throws {
        let container = try ModelContainer(
            for: ExerciseLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext

        modelContext.insert(ExerciseLibraryEntry(name: "卧推", isBuiltin: true))
        try modelContext.save()

        ExerciseLibraryStore.ensureBuiltinEntries(in: modelContext)
        ExerciseLibraryStore.ensureBuiltinEntries(in: modelContext)

        let entries = try modelContext.fetch(FetchDescriptor<ExerciseLibraryEntry>())
        let benchPressEntries = entries.filter { $0.name == "卧推" }

        XCTAssertEqual(entries.count, ExerciseLibraryCatalog.builtinExerciseNames.count)
        XCTAssertEqual(benchPressEntries.count, 1)
    }

    @MainActor
    func testExerciseLibraryStoreAddsCustomEntry() throws {
        let container = try ModelContainer(
            for: ExerciseLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext

        try ExerciseLibraryStore.addCustomEntry(
            named: " 上斜卧推 ",
            in: modelContext
        )

        let entries = try modelContext.fetch(FetchDescriptor<ExerciseLibraryEntry>())

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "上斜卧推")
        XCTAssertFalse(entries[0].isBuiltin)
    }

    @MainActor
    func testExerciseLibraryStoreRejectsDuplicateCustomEntryNames() throws {
        let container = try ModelContainer(
            for: ExerciseLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext

        modelContext.insert(ExerciseLibraryEntry(name: "卧推", isBuiltin: true))
        try modelContext.save()

        XCTAssertThrowsError(
            try ExerciseLibraryStore.addCustomEntry(
                named: " 卧推 ",
                in: modelContext
            )
        ) { error in
            XCTAssertEqual(error as? ExerciseLibraryStoreError, .duplicateName)
        }
    }

    func testExerciseLibraryAutocompleteSuggestionsIncludeBuiltinAndCustomEntries() {
        let entries = [
            ExerciseLibraryEntry(name: "卧推", isBuiltin: true),
            ExerciseLibraryEntry(name: "上斜卧推", isBuiltin: false),
            ExerciseLibraryEntry(name: "深蹲", isBuiltin: true),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "卧",
            from: entries
        )

        XCTAssertEqual(suggestions.map(\.name), ["卧推", "上斜卧推"])
        XCTAssertEqual(suggestions.map(\.isBuiltin), [true, false])
    }

    func testExerciseLibraryAutocompleteSuggestionsReturnAllMatchesForEmptyQuery() {
        let entries = [
            ExerciseLibraryEntry(name: "卧推", isBuiltin: true),
            ExerciseLibraryEntry(name: "深蹲", isBuiltin: true),
            ExerciseLibraryEntry(name: "硬拉", isBuiltin: true),
            ExerciseLibraryEntry(name: "肩推", isBuiltin: true),
            ExerciseLibraryEntry(name: "引体向上", isBuiltin: true),
            ExerciseLibraryEntry(name: "杠铃划船", isBuiltin: true),
            ExerciseLibraryEntry(name: "上斜卧推", isBuiltin: false),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "",
            from: entries
        )

        XCTAssertEqual(suggestions.count, entries.count)
        XCTAssertTrue(suggestions.contains { $0.name == "上斜卧推" })
    }

    func testExerciseLibraryAutocompleteSuggestionsHideExactMatches() {
        let entries = [
            ExerciseLibraryEntry(name: "卧推", isBuiltin: true),
            ExerciseLibraryEntry(name: "窄握卧推", isBuiltin: false),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "卧推",
            from: entries
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testExerciseLibraryAutocompleteSuggestionsMatchChineseNameByFullPinyin() {
        let entries = [
            ExerciseLibraryEntry(name: "深蹲", isBuiltin: true),
            ExerciseLibraryEntry(name: "硬拉", isBuiltin: true),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "shen",
            from: entries
        )

        XCTAssertEqual(suggestions.map(\.name), ["深蹲"])
    }

    func testExerciseLibraryAutocompleteSuggestionsMatchChineseNameByPinyinInitials() {
        let entries = [
            ExerciseLibraryEntry(name: "深蹲", isBuiltin: true),
            ExerciseLibraryEntry(name: "肩推", isBuiltin: true),
            ExerciseLibraryEntry(name: "上斜卧推", isBuiltin: false),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "s",
            from: entries
        )

        XCTAssertEqual(suggestions.map(\.name), ["深蹲", "上斜卧推"])
    }

    func testExerciseLibraryAutocompleteSuggestionsKeepShowingForExactPinyinMatch() {
        let entries = [
            ExerciseLibraryEntry(name: "深蹲", isBuiltin: true),
            ExerciseLibraryEntry(name: "硬拉", isBuiltin: true),
        ]

        let suggestions = ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: "shendun",
            from: entries
        )

        XCTAssertEqual(suggestions.map(\.name), ["深蹲"])
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
        XCTAssertEqual(parsedText.planLines[0].weight, .numeric(20))
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

    func testWorkoutNoteAcceptsAlternativePlanLineSeparators() {
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 X 8 X 5
            22.5 × 6 × 3
            24 * 10 * 4
            """
        )

        let parsedText = note.parsedText()

        XCTAssertEqual(parsedText.planLines.count, 3)
        XCTAssertEqual(parsedText.planLines.map(\.rawText), [
            "20 X 8 X 5",
            "22.5 × 6 × 3",
            "24 * 10 * 4",
        ])
        XCTAssertEqual(parsedText.planLines.map(\.weight), [.numeric(20), .numeric(22.5), .numeric(24)])
        XCTAssertEqual(parsedText.planLines.map(\.reps), [8, 6, 10])
        XCTAssertEqual(parsedText.planLines.map(\.targetSets), [5, 3, 4])
    }

    func testWorkoutNoteAcceptsBodyweightPlanLineWeightsCaseInsensitively() {
        let note = WorkoutNote(
            rawText: """
            @引体向上
            BW x 8 x 3
            bodyweight X 6 X 2
            """
        )

        let parsedText = note.parsedText()

        XCTAssertEqual(parsedText.planLines.count, 2)
        XCTAssertEqual(parsedText.planLines.map(\.weight), [.bodyweight, .bodyweight])
        XCTAssertEqual(parsedText.planLines.map(\.reps), [8, 6])
        XCTAssertEqual(parsedText.planLines.map(\.targetSets), [3, 2])
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

    func testTrainingEditorTextLayoutBuildsExerciseAutocompleteRequestFromCurrentLine() {
        let text = """
        备注
          @卧
        20 x 8 x 5
        """
        let lines = TrainingEditorTextLayout.lines(in: text)
        let selectedRange = NSRange(
            location: lines[1].contentRange.location + 4,
            length: 0
        )

        let request = TrainingEditorTextLayout.exerciseAutocompleteRequest(
            text: text,
            selectedRange: selectedRange
        )

        XCTAssertEqual(request?.lineIndex, 1)
        XCTAssertEqual(request?.query, "卧")
        XCTAssertEqual(
            request?.replacementRange,
            NSRange(location: lines[1].contentRange.location + 2, length: 2)
        )
    }

    func testTrainingEditorTextLayoutDoesNotBuildExerciseAutocompleteRequestForInvalidExerciseLine() {
        let text = """
        @@卧推
        20 x 8 x 5
        """
        let selectedRange = NSRange(location: 3, length: 0)

        let request = TrainingEditorTextLayout.exerciseAutocompleteRequest(
            text: text,
            selectedRange: selectedRange
        )

        XCTAssertNil(request)
    }

    func testTrainingEditorTextLayoutAppliesExerciseAutocompleteAndMovesCursorToLineEnd() {
        let text = """
          @卧
        20 x 8 x 5
        """
        let lines = TrainingEditorTextLayout.lines(in: text)
        let request = TrainingEditorTextLayout.exerciseAutocompleteRequest(
            text: text,
            selectedRange: NSRange(
                location: lines[0].contentRange.location + 4,
                length: 0
            )
        )
        XCTAssertNotNil(request)

        let insertion = TrainingEditorTextLayout.applyExerciseAutocomplete(
            exerciseName: "卧推",
            to: text,
            request: request!
        )

        XCTAssertEqual(
            insertion.text,
            """
              @卧推
            20 x 8 x 5
            """
        )
        XCTAssertEqual(
            insertion.selectedRange,
            NSRange(location: lines[0].contentRange.location + 5, length: 0)
        )
    }

    func testTrainingEditorTextLayoutReturnsHighlightRangesForValidExerciseLinesOnly() {
        let text = """
        备注
          @深蹲  
        @@卧推
        @硬拉
        """

        let highlightRanges = TrainingEditorTextLayout.exerciseLineHighlightRanges(in: text)
        let highlightedTexts = highlightRanges.map { (text as NSString).substring(with: $0) }

        XCTAssertEqual(highlightedTexts, ["@深蹲", "@硬拉"])
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
    func testTrainingEditorSessionClearsPlanLineAndProgressDuringInvalidEdit() {
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
            """
        )

        XCTAssertEqual(
            session.noteText,
            """
            @卧推
            20 x 8 x
            """
        )
        XCTAssertTrue(session.parsedText.planLines.isEmpty)
        XCTAssertTrue(session.draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingEditorSessionClearsProgressWhenPlanLineBecomesInvalid() {
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
            """
        )

        XCTAssertTrue(session.parsedText.planLines.isEmpty)
        XCTAssertTrue(session.draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingEditorSessionClearsProgressWhenPlanLineDefinitionChanges() {
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
            """
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 4"])
        XCTAssertTrue(session.draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingEditorSessionMigratesProgressWhenLineIsInsertedAbovePlanLine() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            20 x 8 x 5
            最后两组感觉很重
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])
        session.incrementProgress(for: session.parsedText.planLines[0])

        session.handleEditedText(
            """
            @卧推
            训练前热身完成
            20 x 8 x 5
            最后两组感觉很重
            """
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.lineIndex), [2])
        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertNil(session.draftProgressState.completedSets(forLineIndex: 1))
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 2), 2)
    }

    @MainActor
    func testTrainingEditorSessionMigratesProgressWhenLineIsDeletedAbovePlanLine() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            训练前热身完成
            20 x 8 x 5
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])

        session.handleEditedText(
            """
            @卧推
            20 x 8 x 5
            """
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.lineIndex), [1])
        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertNil(session.draftProgressState.completedSets(forLineIndex: 2))
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 1), 1)
    }

    @MainActor
    func testTrainingEditorSessionRestoresProgressWhenPlanLineBecomesValidAgain() {
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
            """
        )

        XCTAssertTrue(session.parsedText.planLines.isEmpty)
        XCTAssertTrue(session.draftProgressState.isEmpty)

        session.handleEditedText(
            """
            @卧推
            20 x 8 x 5
            """
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 1), 1)
    }

    @MainActor
    func testTrainingEditorSessionRestoresProgressAfterTransientInvalidStateWhileDeletingLineAbove() {
        let session = TrainingEditorSession(
            initialRawText: """
            @卧推
            训练前热身完成
            20 x 8 x 5
            """
        )

        session.incrementProgress(for: session.parsedText.planLines[0])

        session.handleEditedText(
            """
            @卧推
            训练前热身完成20 x 8 x 5
            """
        )

        XCTAssertTrue(session.parsedText.planLines.isEmpty)
        XCTAssertTrue(session.draftProgressState.isEmpty)

        session.handleEditedText(
            """
            @卧推
            20 x 8 x 5
            """
        )

        XCTAssertEqual(session.parsedText.planLines.map(\.lineIndex), [1])
        XCTAssertEqual(session.parsedText.planLines.map(\.rawText), ["20 x 8 x 5"])
        XCTAssertEqual(session.draftProgressState.completedSets(forLineIndex: 1), 1)
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

    func testWorkoutTextProgressUpdaterFinalizesBodyweightPlanLinesAsBW() {
        let parseResult = WorkoutTextParser.parse(
            rawText: """
            @引体向上
            bodyweight x 8 x 3
            """
        )
        let draftProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 2)]
        )

        let finalizedText = WorkoutTextProgressUpdater.finalizeWorkout(
            in: parseResult,
            draftProgress: draftProgressState
        )

        XCTAssertEqual(
            finalizedText,
            """
            @引体向上
            BW x 8 x 2
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
        let originalLogHandler = QuickRepDiagnostics.logHandler
        var logMessages: [String] = []
        QuickRepDiagnostics.logHandler = { logMessages.append($0) }
        defer { QuickRepDiagnostics.logHandler = originalLogHandler }

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
                domain: "QuickRepTests",
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
        let originalLogHandler = QuickRepDiagnostics.logHandler
        var logMessages: [String] = []
        QuickRepDiagnostics.logHandler = { logMessages.append($0) }
        defer { QuickRepDiagnostics.logHandler = originalLogHandler }

        let note = WorkoutNote(
            rawText: "@卧推\n20 x 8 x 5",
            draftProgressData: Data("not-json".utf8)
        )

        XCTAssertTrue(note.draftProgressState.isEmpty)
        XCTAssertTrue(
            logMessages.contains(where: { $0.contains("Failed to decode workout draft progress") })
        )
    }

    func testWorkoutHistoryCardEntriesBuildsBestSetForEachExercise() {
        let record = WorkoutHistoryRecord(
            rawText: """
            @深蹲
            20 x 5 x 3
            40 x 3 x 2
            @引体向上
            10 x 5 x 3
            12.5 x 4 x 2
            """
        )

        XCTAssertEqual(
            record.historyCardEntries,
            [
                WorkoutHistoryCardEntry(exerciseName: "深蹲", bestSetText: "40 x 3 x 2"),
                WorkoutHistoryCardEntry(exerciseName: "引体向上", bestSetText: "12.5 x 4 x 2"),
            ]
        )
    }

    func testWorkoutHistoryCardEntriesBreaksWeightTiesByRepsAndSets() {
        let record = WorkoutHistoryRecord(
            rawText: """
            @卧推
            40 x 5 x 2
            40 x 6 x 1
            40 x 6 x 3
            """
        )

        XCTAssertEqual(
            record.historyCardEntries,
            [WorkoutHistoryCardEntry(exerciseName: "卧推", bestSetText: "40 x 6 x 3")]
        )
    }

    func testWorkoutHistoryCardEntriesFormatsBodyweightAsBW() {
        let record = WorkoutHistoryRecord(
            rawText: """
            @引体向上
            bw x 8 x 3
            """
        )

        XCTAssertEqual(
            record.historyCardEntries,
            [WorkoutHistoryCardEntry(exerciseName: "引体向上", bestSetText: "BW x 8 x 3")]
        )
    }

    func testWorkoutHistoryCardDateTextUsesYYYYMMDD() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let finishedAt = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 4,
                    day: 6,
                    hour: 12,
                    minute: 0
                )
            )
        )
        let record = WorkoutHistoryRecord(
            rawText: """
            @卧推
            20 x 5 x 3
            """,
            finishedAt: finishedAt
        )

        XCTAssertEqual(record.historyCardDateText, "2026-04-06")
    }

    func testWorkoutHistoryCardEntriesSkipsExerciseWithoutValidSet() {
        let record = WorkoutHistoryRecord(
            rawText: """
            @卧推
            今天状态一般
            20 x 5
            @深蹲
            备注
            """
        )

        XCTAssertTrue(record.historyCardEntries.isEmpty)
    }

    @MainActor
    func testTrainingHistoryStoreRecordsNonEmptyFinishedWorkoutAndClearsDraft() throws {
        let container = try ModelContainer(
            for: WorkoutNote.self,
            WorkoutHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext
        let finishedAt = Date(timeIntervalSince1970: 1_000)
        let draftNote = WorkoutNote(rawText: "@卧推\n20 x 8 x 5")
        draftNote.draftProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 2)]
        )
        modelContext.insert(draftNote)
        try modelContext.save()

        try TrainingHistoryStore.recordFinishedWorkout(
            finalizedRawText: "@卧推\n20 x 8 x 4",
            draftWorkoutNote: draftNote,
            modelContext: modelContext,
            finishedAt: finishedAt
        )

        let historyRecords = try modelContext.fetch(
            FetchDescriptor<WorkoutHistoryRecord>(
                sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
            )
        )
        XCTAssertEqual(historyRecords.count, 1)
        XCTAssertEqual(historyRecords[0].rawText, "@卧推\n20 x 8 x 4")
        XCTAssertEqual(historyRecords[0].finishedAt, finishedAt)

        let persistedNotes = try modelContext.fetch(FetchDescriptor<WorkoutNote>())
        XCTAssertEqual(persistedNotes.count, 1)
        XCTAssertEqual(persistedNotes[0].rawText, "")
        XCTAssertTrue(persistedNotes[0].draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingHistoryStoreSkipsEmptyFinishedWorkoutButClearsDraft() throws {
        let container = try ModelContainer(
            for: WorkoutNote.self,
            WorkoutHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext
        let draftNote = WorkoutNote(rawText: "@卧推\n20 x 8 x 5")
        draftNote.draftProgressState = WorkoutDraftProgressState(
            entries: [WorkoutDraftProgressEntry(lineIndex: 1, completedSets: 1)]
        )
        modelContext.insert(draftNote)
        try modelContext.save()

        try TrainingHistoryStore.recordFinishedWorkout(
            finalizedRawText: "  \n ",
            draftWorkoutNote: draftNote,
            modelContext: modelContext
        )

        let historyRecords = try modelContext.fetch(FetchDescriptor<WorkoutHistoryRecord>())
        XCTAssertTrue(historyRecords.isEmpty)

        let persistedNotes = try modelContext.fetch(FetchDescriptor<WorkoutNote>())
        XCTAssertEqual(persistedNotes.count, 1)
        XCTAssertEqual(persistedNotes[0].rawText, "")
        XCTAssertTrue(persistedNotes[0].draftProgressState.isEmpty)
    }

    @MainActor
    func testTrainingHomeScreenPrimaryWorkoutButtonTitleReturnsToStartAfterFinishingWorkout() throws {
        let container = try ModelContainer(
            for: WorkoutNote.self,
            WorkoutHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext
        let draftNote = WorkoutNote(rawText: "@卧推\n20 x 8 x 5")
        modelContext.insert(draftNote)
        try modelContext.save()

        try TrainingHistoryStore.recordFinishedWorkout(
            finalizedRawText: "@卧推\n20 x 8 x 4",
            draftWorkoutNote: draftNote,
            modelContext: modelContext
        )

        let persistedNote = try XCTUnwrap(
            modelContext.fetch(FetchDescriptor<WorkoutNote>()).first
        )
        XCTAssertEqual(
            TrainingHomeScreen.primaryWorkoutButtonTitle(for: persistedNote),
            "开始训练"
        )
    }

    @MainActor
    func testTrainingHomeScreenPrimaryWorkoutButtonTitleStaysStartWithHistoryButNoDraft() throws {
        let container = try ModelContainer(
            for: WorkoutNote.self,
            WorkoutHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext
        let emptyDraftNote = WorkoutNote(rawText: "")
        let historyRecord = WorkoutHistoryRecord(rawText: "@卧推\n20 x 8 x 4")

        modelContext.insert(emptyDraftNote)
        modelContext.insert(historyRecord)
        try modelContext.save()

        let persistedDraftNote = try XCTUnwrap(
            modelContext.fetch(FetchDescriptor<WorkoutNote>()).first
        )
        let persistedHistoryRecords = try modelContext.fetch(
            FetchDescriptor<WorkoutHistoryRecord>()
        )

        XCTAssertEqual(
            TrainingHomeScreen.primaryWorkoutButtonTitle(for: persistedDraftNote),
            "开始训练"
        )
        XCTAssertEqual(persistedHistoryRecords.count, 1)
    }

    @MainActor
    func testWorkoutHistoryRecordFetchSortsByFinishedAtDescending() throws {
        let container = try ModelContainer(
            for: WorkoutHistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let modelContext = container.mainContext
        modelContext.insert(
            WorkoutHistoryRecord(
                rawText: "older",
                finishedAt: Date(timeIntervalSince1970: 1_000)
            )
        )
        modelContext.insert(
            WorkoutHistoryRecord(
                rawText: "newer",
                finishedAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        try modelContext.save()

        let sortedRecords = try modelContext.fetch(
            FetchDescriptor<WorkoutHistoryRecord>(
                sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
            )
        )
        XCTAssertEqual(sortedRecords.map(\.rawText), ["newer", "older"])
    }
}
