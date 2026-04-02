import Foundation

enum WorkoutTextProgressUpdater {
    static func incrementProgress(
        for planLineID: UUID,
        in parseResult: WorkoutTextParseResult,
        draftProgress: WorkoutDraftProgressState
    ) -> WorkoutDraftProgressState? {
        guard let planLine = parseResult.planLines.first(where: { $0.id == planLineID }) else {
            return nil
        }

        let completedSets = draftProgress.completedSets(forLineIndex: planLine.lineIndex) ?? 0
        guard completedSets < planLine.targetSets else {
            return nil
        }

        return draftProgress.settingCompletedSets(
            completedSets + 1,
            forLineIndex: planLine.lineIndex
        )
    }

    static func reconcileDraftProgress(
        afterEditing rawText: String,
        previousParseResult: WorkoutTextParseResult,
        previousDraftProgress: WorkoutDraftProgressState
    ) -> WorkoutDraftProgressState {
        let reconciledSnapshot = WorkoutTextSnapshot(
            rawText: rawText,
            reconcilingWith: previousParseResult.snapshot
        )
        let nextParseResult = WorkoutTextParser.parse(snapshot: reconciledSnapshot)
        return reconcileDraftProgress(
            nextParseResult: nextParseResult,
            previousParseResult: previousParseResult,
            previousDraftProgress: previousDraftProgress
        )
    }

    static func reconcileDraftProgress(
        nextParseResult: WorkoutTextParseResult,
        previousParseResult: WorkoutTextParseResult,
        previousDraftProgress: WorkoutDraftProgressState
    ) -> WorkoutDraftProgressState {
        let previousPlanLinesByLineIndex = Dictionary(
            uniqueKeysWithValues: previousParseResult.planLines.map { ($0.lineIndex, $0) }
        )
        let nextPlanLinesByID = Dictionary(
            uniqueKeysWithValues: nextParseResult.planLines.map { ($0.id, $0) }
        )

        let retainedEntries = previousDraftProgress.entries.compactMap { entry -> WorkoutDraftProgressEntry? in
            guard
                let previousPlanLine = previousPlanLinesByLineIndex[entry.lineIndex],
                let nextPlanLine = nextPlanLinesByID[previousPlanLine.id],
                nextPlanLine.weight == previousPlanLine.weight,
                nextPlanLine.reps == previousPlanLine.reps,
                nextPlanLine.targetSets == previousPlanLine.targetSets
            else {
                return nil
            }

            let completedSets = min(
                max(entry.completedSets, 0),
                nextPlanLine.targetSets
            )
            guard completedSets > 0 else {
                return nil
            }

            return WorkoutDraftProgressEntry(
                lineIndex: nextPlanLine.lineIndex,
                completedSets: completedSets
            )
        }

        return WorkoutDraftProgressState(entries: retainedEntries)
    }

    static func finalizeWorkout(
        in parseResult: WorkoutTextParseResult,
        draftProgress: WorkoutDraftProgressState
    ) -> String {
        let planLineByID = Dictionary(uniqueKeysWithValues: parseResult.planLines.map { ($0.id, $0) })

        let finalizedLines = parseResult.snapshot.lines.compactMap { line -> String? in
            guard let planLine = planLineByID[line.id] else {
                return line.rawText
            }

            let finalizedSets = draftProgress.completedSets(forLineIndex: planLine.lineIndex) ?? 0
            guard finalizedSets > 0 else {
                return nil
            }

            return "\(planLine.formattedWeight) x \(planLine.reps) x \(finalizedSets)"
        }

        return finalizedLines.joined(separator: "\n")
    }
}

private extension PlanLine {
    var formattedWeight: String {
        guard weight.rounded() == weight else {
            return String(weight)
        }

        return String(Int(weight))
    }
}
