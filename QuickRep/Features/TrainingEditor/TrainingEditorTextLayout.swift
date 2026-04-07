import CoreGraphics
import Foundation

struct TrainingEditorLine: Identifiable, Hashable {
    var id: Int { index }

    let index: Int
    let contentRange: NSRange
    let enclosingRange: NSRange
    let text: String
}

struct TrainingEditorSelectionContext {
    let selectedRange: NSRange
    let currentLine: TrainingEditorLine
    let currentLineRect: CGRect?
}

struct TrainingEditorExerciseAutocompleteRequest: Equatable {
    let lineIndex: Int
    let query: String
    let replacementRange: NSRange
}

struct TrainingEditorExerciseAutocompleteInsertion: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum TrainingEditorTextLayout {
    private static var cachedText: String?
    private static var cachedLines: [TrainingEditorLine] = []

    static func selectionContext(
        text: String,
        selectedRange: NSRange,
        currentLineRect: CGRect? = nil
    ) -> TrainingEditorSelectionContext {
        TrainingEditorSelectionContext(
            selectedRange: selectedRange,
            currentLine: line(containingUTF16Location: selectedRange.location, in: text),
            currentLineRect: currentLineRect
        )
    }

    static func line(
        containingUTF16Location location: Int,
        in text: String
    ) -> TrainingEditorLine {
        let lines = self.lines(in: text)
        guard let lastLine = lines.last else {
            return TrainingEditorLine(
                index: 0,
                contentRange: NSRange(location: 0, length: 0),
                enclosingRange: NSRange(location: 0, length: 0),
                text: ""
            )
        }

        let clampedLocation = clampUTF16Location(location, in: text)

        return lines.first(where: { clampedLocation < NSMaxRange($0.enclosingRange) }) ?? lastLine
    }

    static func lines(in text: String) -> [TrainingEditorLine] {
        if cachedText == text {
            return cachedLines
        }

        let lines = buildLines(in: text)
        cachedText = text
        cachedLines = lines
        return lines
    }

    private static func buildLines(in text: String) -> [TrainingEditorLine] {
        let nsText = text as NSString
        let length = nsText.length
        var lines: [TrainingEditorLine] = []
        var lineStart = 0
        var lineIndex = 0

        for characterIndex in 0..<length where nsText.character(at: characterIndex) == 10 {
            let contentRange = NSRange(location: lineStart, length: characterIndex - lineStart)
            let enclosingRange = NSRange(location: lineStart, length: characterIndex - lineStart + 1)

            lines.append(
                TrainingEditorLine(
                    index: lineIndex,
                    contentRange: contentRange,
                    enclosingRange: enclosingRange,
                    text: nsText.substring(with: contentRange)
                )
            )

            lineStart = characterIndex + 1
            lineIndex += 1
        }

        let finalRange = NSRange(location: lineStart, length: length - lineStart)
        lines.append(
            TrainingEditorLine(
                index: lineIndex,
                contentRange: finalRange,
                enclosingRange: finalRange,
                text: nsText.substring(with: finalRange)
            )
        )

        return lines
    }

    static func selectionRangePreservingLinePosition(
        from oldText: String,
        to newText: String,
        selectedRange: NSRange
    ) -> NSRange {
        let startPosition = linePosition(
            containingUTF16Location: selectedRange.location,
            in: oldText
        )
        let endPosition = linePosition(
            containingUTF16Location: NSMaxRange(selectedRange),
            in: oldText
        )

        let relocatedStart = utf16Location(for: startPosition, in: newText)
        let relocatedEnd = utf16Location(for: endPosition, in: newText)

        return NSRange(
            location: min(relocatedStart, relocatedEnd),
            length: abs(relocatedEnd - relocatedStart)
        )
    }

    static func clampUTF16Location(
        _ location: Int,
        in text: String
    ) -> Int {
        min(max(location, 0), (text as NSString).length)
    }

    static func exerciseAutocompleteRequest(
        text: String,
        selectedRange: NSRange
    ) -> TrainingEditorExerciseAutocompleteRequest? {
        guard selectedRange.length == 0 else {
            return nil
        }

        let currentLine = line(
            containingUTF16Location: selectedRange.location,
            in: text
        )
        let caretLocation = clampUTF16Location(selectedRange.location, in: text)
        let lineStart = currentLine.contentRange.location
        let lineLength = currentLine.contentRange.length
        let leadingWhitespaceLength = currentLine.text.prefix {
            $0.isWhitespace && !$0.isNewline
        }.utf16.count

        guard lineLength > leadingWhitespaceLength else {
            return nil
        }

        let tokenRange = NSRange(
            location: lineStart + leadingWhitespaceLength,
            length: lineLength - leadingWhitespaceLength
        )
        let tokenText = (text as NSString).substring(with: tokenRange)

        guard
            tokenText.hasPrefix("@"),
            !tokenText.dropFirst().hasPrefix("@"),
            caretLocation >= tokenRange.location + 1,
            caretLocation <= NSMaxRange(tokenRange)
        else {
            return nil
        }

        let queryRange = NSRange(
            location: tokenRange.location + 1,
            length: caretLocation - tokenRange.location - 1
        )
        let query = (text as NSString).substring(with: queryRange)

        return TrainingEditorExerciseAutocompleteRequest(
            lineIndex: currentLine.index,
            query: query,
            replacementRange: tokenRange
        )
    }

    static func applyExerciseAutocomplete(
        exerciseName: String,
        to text: String,
        request: TrainingEditorExerciseAutocompleteRequest
    ) -> TrainingEditorExerciseAutocompleteInsertion {
        let replacementText = "@\(exerciseName)"
        let nextText = (text as NSString).replacingCharacters(
            in: request.replacementRange,
            with: replacementText
        )
        let nextSelectedRange = NSRange(
            location: request.replacementRange.location + replacementText.utf16.count,
            length: 0
        )

        return TrainingEditorExerciseAutocompleteInsertion(
            text: nextText,
            selectedRange: nextSelectedRange
        )
    }

    static func exerciseLineHighlightRanges(in text: String) -> [NSRange] {
        lines(in: text).compactMap(exerciseLineHighlightRange(for:))
    }

    static func exerciseLineHighlightRange(for line: TrainingEditorLine) -> NSRange? {
        let leadingWhitespaceLength = line.text.prefix {
            $0.isWhitespace && !$0.isNewline
        }.utf16.count
        let trailingWhitespaceLength = String(
            line.text.reversed().prefix { $0.isWhitespace && !$0.isNewline }.reversed()
        ).utf16.count
        let visibleLength = line.contentRange.length - leadingWhitespaceLength - trailingWhitespaceLength

        guard visibleLength > 0 else {
            return nil
        }

        let visibleLineTextRange = NSRange(location: leadingWhitespaceLength, length: visibleLength)
        let visibleLineText = (line.text as NSString).substring(with: visibleLineTextRange)

        guard parsedExerciseName(from: visibleLineText) != nil else {
            return nil
        }

        return NSRange(
            location: line.contentRange.location + leadingWhitespaceLength,
            length: visibleLength
        )
    }

    private static func linePosition(
        containingUTF16Location location: Int,
        in text: String
    ) -> TrainingEditorLinePosition {
        let line = line(containingUTF16Location: location, in: text)
        let clampedLocation = clampUTF16Location(location, in: text)
        let offset = min(
            max(clampedLocation - line.enclosingRange.location, 0),
            line.enclosingRange.length
        )

        return TrainingEditorLinePosition(
            lineIndex: line.index,
            offsetInEnclosingRange: offset
        )
    }

    private static func utf16Location(
        for position: TrainingEditorLinePosition,
        in text: String
    ) -> Int {
        let lines = lines(in: text)
        guard let lastLine = lines.last else {
            return 0
        }

        let lineIndex = min(max(position.lineIndex, 0), lastLine.index)
        let line = lines[lineIndex]
        let offset = min(max(position.offsetInEnclosingRange, 0), line.enclosingRange.length)

        return line.enclosingRange.location + offset
    }

    private static func parsedExerciseName(from lineText: String) -> String? {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)

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
}

private struct TrainingEditorLinePosition {
    let lineIndex: Int
    let offsetInEnclosingRange: Int
}
