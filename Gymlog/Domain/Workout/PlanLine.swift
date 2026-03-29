import Foundation

struct PlanLine: Identifiable, Hashable {
    let id: UUID
    let lineIndex: Int
    let exerciseBlockId: UUID
    let weight: Double
    let reps: Int
    let targetSets: Int
    let completedSets: Int?
    let rawText: String

    init(
        id: UUID = UUID(),
        lineIndex: Int,
        exerciseBlockId: UUID,
        weight: Double,
        reps: Int,
        targetSets: Int,
        completedSets: Int? = nil,
        rawText: String
    ) {
        self.id = id
        self.lineIndex = lineIndex
        self.exerciseBlockId = exerciseBlockId
        self.weight = weight
        self.reps = reps
        self.targetSets = targetSets
        self.completedSets = completedSets
        self.rawText = rawText
    }

    var state: PlanLineState {
        PlanLineState.infer(from: rawText, completedSets: completedSets)
    }

    func state(isFinalizedRecord: Bool) -> PlanLineState {
        PlanLineState.infer(
            from: rawText,
            completedSets: completedSets,
            isFinalizedRecord: isFinalizedRecord
        )
    }
}

enum PlanLineState: Equatable {
    case planned
    case inProgress
    case finalized

    static func infer(
        from rawText: String,
        completedSets: Int?,
        isFinalizedRecord: Bool = false
    ) -> PlanLineState {
        if completedSets != nil || rawText.hasInProgressSuffix {
            return .inProgress
        }

        return isFinalizedRecord ? .finalized : .planned
    }
}

private extension String {
    var hasInProgressSuffix: Bool {
        let pattern = #"\s+\d+\s*/\s*\d+\s*$"#
        return range(of: pattern, options: .regularExpression) != nil
    }
}
