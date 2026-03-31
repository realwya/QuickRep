import Foundation

struct WorkoutTextLine: Identifiable, Hashable {
    let id: UUID
    let index: Int
    let rawText: String

    init(
        id: UUID = UUID(),
        index: Int,
        rawText: String
    ) {
        self.id = id
        self.index = index
        self.rawText = rawText
    }
}

struct WorkoutTextSnapshot: Hashable {
    let lines: [WorkoutTextLine]

    init(rawText: String, reconcilingWith previous: WorkoutTextSnapshot? = nil) {
        self = Self.reconciled(rawText: rawText, previous: previous)
    }

    var rawText: String {
        lines.map(\.rawText).joined(separator: "\n")
    }

    static func reconciled(
        rawText: String,
        previous: WorkoutTextSnapshot?
    ) -> WorkoutTextSnapshot {
        let lineTexts = splitIntoLineTexts(rawText)
        let previousLines = previous?.lines ?? []
        var searchStart = previousLines.startIndex

        let lines = lineTexts.enumerated().map { index, lineText in
            if let matchedIndex = previousLines[searchStart...].firstIndex(where: { $0.rawText == lineText }) {
                let matchedLine = previousLines[matchedIndex]
                searchStart = previousLines.index(after: matchedIndex)

                return WorkoutTextLine(
                    id: matchedLine.id,
                    index: index,
                    rawText: lineText
                )
            }

            return WorkoutTextLine(
                index: index,
                rawText: lineText
            )
        }

        return WorkoutTextSnapshot(lines: lines)
    }

    private init(lines: [WorkoutTextLine]) {
        self.lines = lines
    }

    private static func splitIntoLineTexts(_ rawText: String) -> [String] {
        rawText.components(separatedBy: "\n")
    }
}
