import Foundation
import XCTest
@testable import Gymlog

final class GymlogTests: XCTestCase {
    func testWorkoutNoteKeepsRawTextAsSingleSourceOfTruth() {
        let updatedAt = Date(timeIntervalSince1970: 123)
        let note = WorkoutNote(
            rawText: """
            @卧推
            20 x 8 x 5 3/5
            """,
            updatedAt: updatedAt
        )

        XCTAssertFalse(note.rawText.isEmpty)
        XCTAssertEqual(note.updatedAt, updatedAt)
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

    func testPlanLineRecognizesInProgressState() {
        let blockID = UUID()
        let line = PlanLine(
            lineIndex: 1,
            exerciseBlockId: blockID,
            weight: 20,
            reps: 8,
            targetSets: 5,
            completedSets: 3,
            rawText: "20 x 8 x 5 3/5"
        )

        XCTAssertEqual(line.completedSets, 3)
        XCTAssertEqual(line.targetSets, 5)
        XCTAssertEqual(line.state, .inProgress)
    }

    func testPlanLineSupportsFinalizedSemanticStateWithContext() {
        let line = PlanLine(
            lineIndex: 1,
            exerciseBlockId: UUID(),
            weight: 20,
            reps: 8,
            targetSets: 4,
            rawText: "20 x 8 x 4"
        )

        XCTAssertEqual(line.state, .planned)
        XCTAssertEqual(line.state(isFinalizedRecord: true), .finalized)
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
        20 x 8 x 5 3/5
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
}
