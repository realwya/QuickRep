import Foundation

struct ExerciseBlock: Identifiable, Hashable {
    let id: UUID
    let exerciseName: String
    let startLineIndex: Int
    let endLineIndex: Int

    init(
        id: UUID = UUID(),
        exerciseName: String,
        startLineIndex: Int,
        endLineIndex: Int
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.startLineIndex = startLineIndex
        self.endLineIndex = endLineIndex
    }
}
