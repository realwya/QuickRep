import Foundation

enum WorkoutTextParser {
    static func parse(
        rawText: String,
        reconcilingWith previous: WorkoutTextSnapshot? = nil
    ) -> WorkoutTextParseResult {
        parse(
            snapshot: WorkoutTextSnapshot(
                rawText: rawText,
                reconcilingWith: previous
            )
        )
    }

    static func parse(snapshot: WorkoutTextSnapshot) -> WorkoutTextParseResult {
        var exerciseBlocks: [ExerciseBlock] = []
        var planLines: [PlanLine] = []
        var noteLines: [WorkoutTextNoteLine] = []
        var currentExerciseBlockIndex: Int?

        for line in snapshot.lines {
            if let exerciseName = parseExerciseName(from: line.rawText) {
                closeCurrentExerciseBlock(
                    endingAt: line.index - 1,
                    in: &exerciseBlocks,
                    currentIndex: currentExerciseBlockIndex
                )

                exerciseBlocks.append(
                    ExerciseBlock(
                        id: line.id,
                        exerciseName: exerciseName,
                        startLineIndex: line.index,
                        endLineIndex: line.index
                    )
                )
                currentExerciseBlockIndex = exerciseBlocks.indices.last
                continue
            }

            guard let currentExerciseBlockIndex else {
                noteLines.append(
                    WorkoutTextNoteLine(
                        id: line.id,
                        lineIndex: line.index,
                        exerciseBlockId: nil,
                        rawText: line.rawText
                    )
                )
                continue
            }

            let exerciseBlock = exerciseBlocks[currentExerciseBlockIndex]

            if let parsedPlanLine = parsePlanLine(from: line.rawText) {
                planLines.append(
                    PlanLine(
                        id: line.id,
                        lineIndex: line.index,
                        exerciseBlockId: exerciseBlock.id,
                        weight: parsedPlanLine.weight,
                        reps: parsedPlanLine.reps,
                        targetSets: parsedPlanLine.targetSets,
                        rawText: line.rawText
                    )
                )
                continue
            }

            noteLines.append(
                WorkoutTextNoteLine(
                    id: line.id,
                    lineIndex: line.index,
                    exerciseBlockId: exerciseBlock.id,
                    rawText: line.rawText
                )
            )
        }

        closeCurrentExerciseBlock(
            endingAt: snapshot.lines.last?.index,
            in: &exerciseBlocks,
            currentIndex: currentExerciseBlockIndex
        )

        return WorkoutTextParseResult(
            snapshot: snapshot,
            exerciseBlocks: exerciseBlocks,
            planLines: planLines,
            noteLines: noteLines
        )
    }

    private static func closeCurrentExerciseBlock(
        endingAt endLineIndex: Int?,
        in exerciseBlocks: inout [ExerciseBlock],
        currentIndex: Int?
    ) {
        guard
            let currentIndex,
            exerciseBlocks.indices.contains(currentIndex),
            let endLineIndex
        else {
            return
        }

        let currentBlock = exerciseBlocks[currentIndex]
        exerciseBlocks[currentIndex] = ExerciseBlock(
            id: currentBlock.id,
            exerciseName: currentBlock.exerciseName,
            startLineIndex: currentBlock.startLineIndex,
            endLineIndex: max(currentBlock.startLineIndex, endLineIndex)
        )
    }

    private static func parseExerciseName(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("@") else {
            return nil
        }

        let exerciseName = String(trimmed.dropFirst())
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !exerciseName.isEmpty, !exerciseName.hasPrefix("@") else {
            return nil
        }

        return exerciseName
    }

    private static func parsePlanLine(from rawText: String) -> ParsedPlanLine? {
        guard let plannedMatch = plannedPattern.firstMatch(in: rawText, range: rawText.nsRange) else {
            return nil
        }

        guard
            let weight = rawText.doubleCapture(at: 1, from: plannedMatch),
            let reps = rawText.intCapture(at: 2, from: plannedMatch),
            let targetSets = rawText.intCapture(at: 3, from: plannedMatch),
            weight > 0
        else {
            return nil
        }

        return ParsedPlanLine(
            weight: weight,
            reps: reps,
            targetSets: targetSets
        )
    }

    private static let plannedPattern = try! NSRegularExpression(
        pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*x\s*([1-9][0-9]*)\s*x\s*([1-9][0-9]*)\s*$"#
    )
}

private struct ParsedPlanLine {
    let weight: Double
    let reps: Int
    let targetSets: Int
}

private extension String {
    var nsRange: NSRange {
        NSRange(startIndex..., in: self)
    }

    func intCapture(at index: Int, from match: NSTextCheckingResult) -> Int? {
        guard let value = capture(at: index, from: match) else {
            return nil
        }

        return Int(value)
    }

    func doubleCapture(at index: Int, from match: NSTextCheckingResult) -> Double? {
        guard let value = capture(at: index, from: match) else {
            return nil
        }

        return Double(value)
    }

    func capture(at index: Int, from match: NSTextCheckingResult) -> String? {
        let range = match.range(at: index)

        guard
            range.location != NSNotFound,
            let swiftRange = Range(range, in: self)
        else {
            return nil
        }

        return String(self[swiftRange])
    }
}
