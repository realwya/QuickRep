import Foundation

struct WorkoutTextParseResult: Hashable {
    let snapshot: WorkoutTextSnapshot
    let exerciseBlocks: [ExerciseBlock]
    let planLines: [PlanLine]
    let noteLines: [WorkoutTextNoteLine]
}

struct WorkoutTextNoteLine: Identifiable, Hashable {
    let id: UUID
    let lineIndex: Int
    let exerciseBlockId: UUID?
    let rawText: String
}

struct WorkoutDraftProgressState: Codable, Hashable {
    let entries: [WorkoutDraftProgressEntry]

    init(entries: [WorkoutDraftProgressEntry] = []) {
        let deduplicatedEntries = Dictionary(
            entries.map { ($0.lineIndex, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        self.entries = deduplicatedEntries.values.sorted { lhs, rhs in
            lhs.lineIndex < rhs.lineIndex
        }
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func completedSets(forLineIndex lineIndex: Int) -> Int? {
        entries.first(where: { $0.lineIndex == lineIndex })?.completedSets
    }

    func settingCompletedSets(
        _ completedSets: Int,
        forLineIndex lineIndex: Int
    ) -> WorkoutDraftProgressState {
        let retainedEntries = entries.filter { $0.lineIndex != lineIndex }
        guard completedSets > 0 else {
            return WorkoutDraftProgressState(entries: retainedEntries)
        }

        return WorkoutDraftProgressState(
            entries: retainedEntries + [
                WorkoutDraftProgressEntry(
                    lineIndex: lineIndex,
                    completedSets: completedSets
                )
            ]
        )
    }
}

struct WorkoutDraftProgressEntry: Codable, Hashable {
    let lineIndex: Int
    let completedSets: Int
}
