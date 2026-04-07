import Foundation

struct PlanLine: Identifiable, Hashable {
    let id: UUID
    let lineIndex: Int
    let exerciseBlockId: UUID
    let weight: Double
    let reps: Int
    let targetSets: Int
    let rawText: String

    init(
        id: UUID = UUID(),
        lineIndex: Int,
        exerciseBlockId: UUID,
        weight: Double,
        reps: Int,
        targetSets: Int,
        rawText: String
    ) {
        self.id = id
        self.lineIndex = lineIndex
        self.exerciseBlockId = exerciseBlockId
        self.weight = weight
        self.reps = reps
        self.targetSets = targetSets
        self.rawText = rawText
    }

}
