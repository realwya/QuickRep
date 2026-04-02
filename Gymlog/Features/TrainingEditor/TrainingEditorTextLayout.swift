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
}

private struct TrainingEditorLinePosition {
    let lineIndex: Int
    let offsetInEnclosingRange: Int
}
