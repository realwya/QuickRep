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
        let previousExerciseNamesByBlockID = Dictionary(
            uniqueKeysWithValues: previousParseResult.exerciseBlocks.map { ($0.id, $0.exerciseName) }
        )
        let nextExerciseNamesByBlockID = Dictionary(
            uniqueKeysWithValues: nextParseResult.exerciseBlocks.map { ($0.id, $0.exerciseName) }
        )

        var usedNextLineIndices = Set<Int>()
        var retainedEntries: [WorkoutDraftProgressEntry] = []
        var unmatchedPreviousEntries: [(entry: WorkoutDraftProgressEntry, planLine: PlanLine)] = []

        previousDraftProgress.entries.forEach { entry in
            guard let previousPlanLine = previousPlanLinesByLineIndex[entry.lineIndex] else {
                return
            }

            guard
                let nextPlanLine = nextPlanLinesByID[previousPlanLine.id],
                samePlanDefinition(lhs: nextPlanLine, rhs: previousPlanLine),
                let normalizedEntry = normalizedEntry(
                    from: entry,
                    nextPlanLine: nextPlanLine
                )
            else {
                unmatchedPreviousEntries.append((entry, previousPlanLine))
                return
            }

            retainedEntries.append(normalizedEntry)
            usedNextLineIndices.insert(nextPlanLine.lineIndex)
        }

        let unmatchedPreviousGroups = Dictionary(grouping: unmatchedPreviousEntries) {
            fallbackKey(
                for: $0.planLine,
                exerciseNamesByBlockID: previousExerciseNamesByBlockID
            )
        }
        let nextFallbackGroups = Dictionary(
            grouping: nextParseResult.planLines.filter { usedNextLineIndices.contains($0.lineIndex) == false }
        ) {
            fallbackKey(
                for: $0,
                exerciseNamesByBlockID: nextExerciseNamesByBlockID
            )
        }

        unmatchedPreviousGroups.forEach { key, previousEntries in
            let sortedPreviousEntries = previousEntries.sorted {
                $0.planLine.lineIndex < $1.planLine.lineIndex
            }
            let sortedNextPlanLines = (nextFallbackGroups[key] ?? []).sorted {
                $0.lineIndex < $1.lineIndex
            }

            guard sortedPreviousEntries.count == sortedNextPlanLines.count else {
                return
            }

            zip(sortedPreviousEntries, sortedNextPlanLines).forEach { previousEntry, nextPlanLine in
                guard
                    let normalizedEntry = normalizedEntry(
                        from: previousEntry.entry,
                        nextPlanLine: nextPlanLine
                    )
                else {
                    return
                }

                retainedEntries.append(normalizedEntry)
                usedNextLineIndices.insert(nextPlanLine.lineIndex)
            }
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

private extension WorkoutTextProgressUpdater {
    struct PlanLineFallbackKey: Hashable {
        let exerciseName: String
        let weight: Double
        let reps: Int
        let targetSets: Int
    }

    static func samePlanDefinition(
        lhs: PlanLine,
        rhs: PlanLine
    ) -> Bool {
        lhs.weight == rhs.weight
            && lhs.reps == rhs.reps
            && lhs.targetSets == rhs.targetSets
    }

    static func normalizedEntry(
        from entry: WorkoutDraftProgressEntry,
        nextPlanLine: PlanLine
    ) -> WorkoutDraftProgressEntry? {
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

    static func fallbackKey(
        for planLine: PlanLine,
        exerciseNamesByBlockID: [UUID: String]
    ) -> PlanLineFallbackKey {
        PlanLineFallbackKey(
            exerciseName: exerciseNamesByBlockID[planLine.exerciseBlockId] ?? "",
            weight: planLine.weight,
            reps: planLine.reps,
            targetSets: planLine.targetSets
        )
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
