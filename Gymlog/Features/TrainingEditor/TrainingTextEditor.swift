import SwiftUI
import UIKit

struct TrainingTextEditorSelectionRequest: Equatable {
    let id: UUID
    let selectedRange: NSRange
}

struct TrainingTextEditor: UIViewRepresentable {
    private static let editorLineHeight: CGFloat = 24
    private static let editorFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    private static let editorBaselineOffset: CGFloat = 0
    private static let editorParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = editorLineHeight
        style.maximumLineHeight = editorLineHeight
        style.lineSpacing = 4
        return style
    }()

    @Binding var text: String

    var trackedLineIndices: Set<Int> = []
    var rightGutterWidth: CGFloat = 52
    var selectionRequest: TrainingTextEditorSelectionRequest?
    var onSelectionContextChange: (TrainingEditorSelectionContext) -> Void = { _ in }
    var onTrackedLineRectsChange: ([Int: CGRect]) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.backgroundColor = .clear
        textView.font = Self.editorFont
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartInsertDeleteType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: rightGutterWidth)
        textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityIdentifier = "training-text-editor"

        context.coordinator.applyHighlighting(to: textView)
        context.coordinator.publishEditorState(from: textView)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        let expectedInsets = UIEdgeInsets(top: 16, left: 0, bottom: 16, right: rightGutterWidth)
        if uiView.textContainerInset != expectedInsets {
            uiView.textContainerInset = expectedInsets
        }

        if uiView.text != text {
            let selectionRange = TrainingEditorTextLayout.selectionRangePreservingLinePosition(
                from: uiView.text,
                to: text,
                selectedRange: uiView.selectedRange
            )

            uiView.text = text
            uiView.selectedRange = context.coordinator.clampedSelectedRange(
                selectionRange,
                in: text
            )
            context.coordinator.applyHighlighting(to: uiView)
        }

        if
            let selectionRequest,
            selectionRequest.id != context.coordinator.lastAppliedSelectionRequestID
        {
            uiView.selectedRange = context.coordinator.clampedSelectedRange(
                selectionRequest.selectedRange,
                in: uiView.text
            )
            context.coordinator.lastAppliedSelectionRequestID = selectionRequest.id
            context.coordinator.updateTypingAttributes(for: uiView)
        }

        context.coordinator.publishEditorState(from: uiView)
    }
}

extension TrainingTextEditor {
    final class Coordinator: NSObject, UITextViewDelegate {
        private static let baseTextAttributes: [NSAttributedString.Key: Any] = [
            .font: TrainingTextEditor.editorFont,
            .foregroundColor: UIColor.label,
            .baselineOffset: TrainingTextEditor.editorBaselineOffset,
            .paragraphStyle: TrainingTextEditor.editorParagraphStyle,
        ]
        private static let exerciseLineTextAttributes: [NSAttributedString.Key: Any] = [
            .font: TrainingTextEditor.editorFont,
            .foregroundColor: UIColor.systemBlue,
            .baselineOffset: TrainingTextEditor.editorBaselineOffset,
            .paragraphStyle: TrainingTextEditor.editorParagraphStyle,
        ]

        var parent: TrainingTextEditor
        fileprivate var lastAppliedSelectionRequestID: UUID?

        init(parent: TrainingTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            applyHighlighting(to: textView)
            publishEditorState(from: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            if parent.text != textView.text {
                parent.text = textView.text
            }

            applyHighlighting(to: textView)
            publishEditorState(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateTypingAttributes(for: textView)
            publishEditorState(from: textView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else {
                return
            }

            publishEditorState(from: textView)
        }

        func publishEditorState(from textView: UITextView) {
            let selectedRange = clampedSelectedRange(textView.selectedRange, in: textView.text)

            if selectedRange != textView.selectedRange {
                textView.selectedRange = selectedRange
            }

            let currentLine = TrainingEditorTextLayout.line(
                containingUTF16Location: selectedRange.location,
                in: textView.text
            )

            parent.onSelectionContextChange(
                TrainingEditorSelectionContext(
                    selectedRange: selectedRange,
                    currentLine: currentLine,
                    currentLineRect: lineRect(for: currentLine, in: textView)
                )
            )

            parent.onTrackedLineRectsChange(trackedLineRects(in: textView))
        }

        func applyHighlighting(to textView: UITextView) {
            guard textView.markedTextRange == nil else {
                updateTypingAttributes(for: textView)
                return
            }

            let fullRange = NSRange(location: 0, length: (textView.text as NSString).length)
            let exerciseLineRanges = TrainingEditorTextLayout.exerciseLineHighlightRanges(
                in: textView.text
            )

            textView.textStorage.beginEditing()
            textView.textStorage.setAttributes(Self.baseTextAttributes, range: fullRange)
            exerciseLineRanges.forEach {
                textView.textStorage.addAttributes(Self.exerciseLineTextAttributes, range: $0)
            }
            textView.textStorage.endEditing()

            updateTypingAttributes(for: textView)
        }

        func updateTypingAttributes(for textView: UITextView) {
            let currentLine = TrainingEditorTextLayout.line(
                containingUTF16Location: textView.selectedRange.location,
                in: textView.text
            )
            textView.typingAttributes = typingAttributes(for: currentLine)
        }

        func clampedSelectedRange(
            _ selectedRange: NSRange,
            in text: String
        ) -> NSRange {
            let length = (text as NSString).length
            let location = min(max(selectedRange.location, 0), length)
            let selectedLength = min(max(selectedRange.length, 0), length - location)

            return NSRange(location: location, length: selectedLength)
        }

        private func typingAttributes(
            for line: TrainingEditorLine
        ) -> [NSAttributedString.Key: Any] {
            TrainingEditorTextLayout.exerciseLineHighlightRange(for: line) == nil
                ? Self.baseTextAttributes
                : Self.exerciseLineTextAttributes
        }

        private func trackedLineRects(in textView: UITextView) -> [Int: CGRect] {
            guard !parent.trackedLineIndices.isEmpty else {
                return [:]
            }

            let lines = TrainingEditorTextLayout.lines(in: textView.text)

            return parent.trackedLineIndices.reduce(into: [:]) { result, lineIndex in
                guard
                    lines.indices.contains(lineIndex),
                    let line = lines[safe: lineIndex],
                    let rect = lineRect(for: line, in: textView)
                else {
                    return
                }

                result[lineIndex] = rect
            }
        }

        private func lineRect(
            for line: TrainingEditorLine,
            in textView: UITextView
        ) -> CGRect? {
            guard line.contentRange.length > 0 else {
                return nil
            }

            let textLength = (textView.text as NSString).length
            guard line.contentRange.location < textLength else {
                return nil
            }

            let layoutManager = textView.layoutManager
            let insets = textView.textContainerInset
            let horizontalPadding = textView.textContainer.lineFragmentPadding
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: line.contentRange.location, length: 1),
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else {
                return nil
            }

            let lineFragmentRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            let visibleMinY = lineFragmentRect.minY + insets.top - textView.contentOffset.y
            let lineHeight = max(lineFragmentRect.height, textView.font?.lineHeight ?? 0)

            return CGRect(
                x: insets.left + horizontalPadding,
                y: visibleMinY,
                width: max(textView.bounds.width - insets.left - insets.right - horizontalPadding * 2, 0),
                height: lineHeight
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
