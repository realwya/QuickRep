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
}
