import SwiftData
import SwiftUI

struct TrainingEditorScreen: View {
    private static let autocompleteOverlayMaxHeight: CGFloat = 220

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ExerciseLibraryEntry.name) private var exerciseLibraryEntries: [ExerciseLibraryEntry]
    @Query(sort: \WorkoutNote.updatedAt, order: .reverse) private var workoutNotes: [WorkoutNote]

    @State private var session = TrainingEditorSession(initialRawText: Self.sampleText)
    @State private var selectionContext = TrainingEditorTextLayout.selectionContext(
        text: Self.sampleText,
        selectedRange: NSRange(location: 0, length: 0)
    )
    @State private var trackedLineRects: [Int: CGRect] = [:]
    @State private var lastExitedLine: TrainingEditorLine?
    @State private var autocompleteRequest: TrainingEditorExerciseAutocompleteRequest?
    @State private var selectionRequest: TrainingTextEditorSelectionRequest?

    private static let sampleText = """
    @卧推
    20 x 8 x 5
    最后两组感觉很重
    """

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text("合法计划行会在右侧显示独立圆形进度按钮；训练中的完成组数只保存在圆圈草稿状态里，结束训练时才会收敛为最终正文。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                editorCard

                statusPanel
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
        }
        .onAppear {
            ensureBuiltinExerciseLibraryEntries()
            ensureWorkoutNoteExists()
            syncFromPersistedWorkoutNoteIfNeeded(force: true)
        }
        .onChange(of: workoutNotes.first?.id) { _, _ in
            syncFromPersistedWorkoutNoteIfNeeded(force: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else {
                return
            }

            session.flushPendingPersistence()
        }
        .onDisappear {
            session.flushPendingPersistence()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("训练记录")
                .font(.largeTitle.bold())

            Spacer()

            Button("结束训练") {
                finishWorkout()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var editorCard: some View {
        ZStack(alignment: .topLeading) {
            TrainingTextEditor(
                text: Binding(
                    get: { session.noteText },
                    set: { session.handleEditedText($0, editingLineIndex: selectionContext.currentLine.index) }
                ),
                trackedLineIndices: Set(session.parsedText.planLines.map(\.lineIndex)),
                rightGutterWidth: 52,
                selectionRequest: selectionRequest,
                onSelectionContextChange: {
                    selectionContext = $0
                    autocompleteRequest = TrainingEditorTextLayout.exerciseAutocompleteRequest(
                        text: session.noteText,
                        selectedRange: $0.selectedRange
                    )
                },
                onTrackedLineRectsChange: { trackedLineRects = $0 },
                onLineExit: { line, _ in
                    lastExitedLine = line
                    session.handleLineExit(from: line)
                }
            )

            planLineProgressButtons
            autocompleteSuggestionsOverlay
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var planLineProgressButtons: some View {
        ZStack(alignment: .topLeading) {
            ForEach(session.parsedText.planLines) { planLine in
                if let lineRect = trackedLineRects[planLine.lineIndex] {
                    progressButton(for: planLine)
                        .position(
                            x: lineRect.maxX + 26,
                            y: lineRect.midY
                        )
                }
            }
        }
    }

    private var autocompleteSuggestionsOverlay: some View {
        Group {
            if
                let lineRect = selectionContext.currentLineRect,
                !autocompleteSuggestions.isEmpty
            {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(autocompleteSuggestions) { suggestion in
                            Button {
                                applyAutocompleteSuggestion(suggestion)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("@\(suggestion.name)")
                                        .font(.body.monospaced())
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(suggestion.isBuiltin ? "内置" : "自定义")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 240, alignment: .leading)
                .frame(maxHeight: Self.autocompleteOverlayMaxHeight)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
                .offset(x: lineRect.minX, y: lineRect.maxY + 8)
                .zIndex(1)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("调试状态")
                .font(.headline)

            statusRow(
                title: "光标范围",
                value: "\(selectionContext.selectedRange.location), \(selectionContext.selectedRange.length)"
            )
            statusRow(
                title: "当前行",
                value: "第 \(selectionContext.currentLine.index + 1) 行"
            )
            statusRow(
                title: "当前行文本范围",
                value: rangeDescription(selectionContext.currentLine.contentRange)
            )
            statusRow(
                title: "当前行可视区域",
                value: rectDescription(selectionContext.currentLineRect)
            )
            statusRow(
                title: "最近离开行",
                value: lastExitedLine.map { "第 \($0.index + 1) 行: \(displayText(for: $0.text))" } ?? "尚未切换行"
            )
            statusRow(
                title: "计划行按钮",
                value: session.parsedText.planLines.isEmpty ? "无" : session.parsedText.planLines.map { "第 \($0.lineIndex + 1) 行" }.joined(separator: ", ")
            )
            statusRow(
                title: "动作补全",
                value: autocompleteStatusDescription
            )
            statusRow(
                title: "进行中计划",
                value: session.draftProgressState.entries
                    .map { entryDescription(for: $0) }
                    .joined(separator: ", ")
                    .nilIfEmpty ?? "无"
            )
            if let lastPersistenceErrorMessage = session.lastPersistenceErrorMessage {
                statusRow(
                    title: "最近保存错误",
                    value: lastPersistenceErrorMessage
                )
            }
        }
        .font(.footnote.monospaced())
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
    }

    private func displayText(for text: String) -> String {
        text.isEmpty ? "空行" : text
    }

    private func rangeDescription(_ range: NSRange) -> String {
        "\(range.location)..<\(NSMaxRange(range))"
    }

    private func rectDescription(_ rect: CGRect?) -> String {
        guard let rect else {
            return "不可用"
        }

        return String(
            format: "(x: %.1f, y: %.1f, w: %.1f, h: %.1f)",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height
        )
    }

    private func entryDescription(for entry: WorkoutDraftProgressEntry) -> String {
        guard let planLine = session.parsedText.planLines.first(where: { $0.lineIndex == entry.lineIndex }) else {
            return "第 \(entry.lineIndex + 1) 行"
        }

        return "第 \(entry.lineIndex + 1) 行 \(entry.completedSets)/\(planLine.targetSets)"
    }

    private func progressButton(for planLine: PlanLine) -> some View {
        let completedSets = min(
            session.draftProgressState.completedSets(forLineIndex: planLine.lineIndex) ?? 0,
            planLine.targetSets
        )
        let progress = CGFloat(completedSets) / CGFloat(planLine.targetSets)
        let isComplete = completedSets >= planLine.targetSets

        return Button {
            session.incrementProgress(for: planLine)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemBackground).opacity(0.96))

                Circle()
                    .strokeBorder(Color.secondary.opacity(0.24), lineWidth: 1)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isComplete ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(completedSets)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isComplete ? Color.green : Color.primary)
            }
            .frame(width: 32, height: 32)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("第 \(planLine.lineIndex + 1) 行进度")
        .accessibilityValue("\(completedSets)/\(planLine.targetSets)")
        .disabled(isComplete)
    }

    private func finishWorkout() {
        session.finishWorkout()
    }

    private var autocompleteSuggestions: [ExerciseAutocompleteSuggestion] {
        guard let autocompleteRequest else {
            return []
        }

        return ExerciseLibraryCatalog.autocompleteSuggestions(
            matching: autocompleteRequest.query,
            from: exerciseLibraryEntries
        )
    }

    private var autocompleteStatusDescription: String {
        guard let autocompleteRequest else {
            return "无"
        }

        let queryDescription = autocompleteRequest.query.isEmpty ? "@" : "@\(autocompleteRequest.query)"
        let suggestionsDescription = autocompleteSuggestions
            .map { $0.name }
            .joined(separator: ", ")
            .nilIfEmpty ?? "无候选"

        return "\(queryDescription) -> \(suggestionsDescription)"
    }

    private func ensureWorkoutNoteExists() {
        guard workoutNotes.isEmpty else {
            return
        }

        let workoutNote = WorkoutNote(rawText: Self.sampleText)
        modelContext.insert(workoutNote)
        do {
            try modelContext.save()
        } catch {
            GymlogDiagnostics.log(
                "Failed to save initial workout note: \(error.localizedDescription)"
            )
        }
    }

    private func ensureBuiltinExerciseLibraryEntries() {
        let existingNames = Set(
            exerciseLibraryEntries.map { ExerciseLibraryCatalog.normalize($0.name) }
        )
        let missingBuiltinNames = ExerciseLibraryCatalog.builtinExerciseNames.filter {
            existingNames.contains(ExerciseLibraryCatalog.normalize($0)) == false
        }

        guard missingBuiltinNames.isEmpty == false else {
            return
        }

        missingBuiltinNames.forEach { name in
            modelContext.insert(ExerciseLibraryEntry(name: name, isBuiltin: true))
        }

        do {
            try modelContext.save()
        } catch {
            GymlogDiagnostics.log(
                "Failed to seed builtin exercise library: \(error.localizedDescription)"
            )
        }
    }

    private func applyAutocompleteSuggestion(_ suggestion: ExerciseAutocompleteSuggestion) {
        guard let autocompleteRequest else {
            return
        }

        let insertion = TrainingEditorTextLayout.applyExerciseAutocomplete(
            exerciseName: suggestion.name,
            to: session.noteText,
            request: autocompleteRequest
        )

        session.handleEditedText(
            insertion.text,
            editingLineIndex: autocompleteRequest.lineIndex
        )
        selectionRequest = TrainingTextEditorSelectionRequest(
            id: UUID(),
            selectedRange: insertion.selectedRange
        )
        self.autocompleteRequest = nil
    }

    private func syncFromPersistedWorkoutNoteIfNeeded(force: Bool = false) {
        guard let workoutNote = workoutNotes.first else {
            return
        }

        session.load(
            from: workoutNote,
            force: force,
            saveAction: { workoutNote, state in
                try workoutNote.applyEditorState(
                    rawText: state.rawText,
                    draftProgressState: state.draftProgressState
                )
                try modelContext.save()
            }
        )
    }
}

#Preview {
    TrainingEditorScreen()
        .modelContainer(for: [WorkoutNote.self, ExerciseLibraryEntry.self], inMemory: true)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
