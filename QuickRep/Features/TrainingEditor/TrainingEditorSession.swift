import Foundation
import Observation

enum QuickRepDiagnostics {
    static var logHandler: (String) -> Void = { message in
#if DEBUG
        print(message)
#else
        _ = message
#endif
    }

    static func log(_ message: String) {
#if DEBUG
        logHandler(message)
#else
        _ = message
#endif
    }
}

@MainActor
@Observable
final class TrainingEditorSession {
    struct PersistedState: Equatable {
        let rawText: String
        let draftProgressState: WorkoutDraftProgressState
    }

    private struct DraftProgressRecoveryContext {
        let parseResult: WorkoutTextParseResult
        let draftProgressState: WorkoutDraftProgressState
    }

    typealias SaveAction = @MainActor (WorkoutNote, PersistedState) throws -> Void

    var noteText: String
    var parsedText: WorkoutTextParseResult
    var draftProgressState: WorkoutDraftProgressState
    private(set) var lastPersistenceErrorMessage: String?

    @ObservationIgnored private var workoutNote: WorkoutNote?
    @ObservationIgnored private var loadedWorkoutNoteID: UUID?
    @ObservationIgnored private var saveAction: SaveAction?
    @ObservationIgnored private var pendingPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingPersistence = false
    @ObservationIgnored private let saveDebounceNanoseconds: UInt64
    @ObservationIgnored private var progressRecoveryContext: DraftProgressRecoveryContext?

    init(
        initialRawText: String,
        saveDebounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.noteText = initialRawText
        self.parsedText = WorkoutTextParser.parse(rawText: initialRawText)
        self.draftProgressState = WorkoutDraftProgressState()
        self.saveDebounceNanoseconds = saveDebounceNanoseconds
    }

    deinit {
        pendingPersistenceTask?.cancel()
    }

    func load(
        from workoutNote: WorkoutNote?,
        force: Bool = false,
        saveAction: SaveAction? = nil
    ) {
        guard let workoutNote else {
            return
        }

        if let saveAction {
            self.saveAction = saveAction
        }

        guard force || loadedWorkoutNoteID != workoutNote.id else {
            return
        }

        flushPendingPersistence()

        self.workoutNote = workoutNote
        loadedWorkoutNoteID = workoutNote.id
        noteText = workoutNote.rawText
        draftProgressState = workoutNote.draftProgressState
        parsedText = WorkoutTextParser.parse(rawText: workoutNote.rawText)
        progressRecoveryContext = draftProgressState.isEmpty
            ? nil
            : DraftProgressRecoveryContext(
                parseResult: parsedText,
                draftProgressState: draftProgressState
            )
        lastPersistenceErrorMessage = nil
    }

    func handleEditedText(_ rawText: String) {
        guard rawText != noteText else {
            return
        }

        noteText = rawText
        applyCommittedParseState(for: rawText)
        scheduleDebouncedPersistence()
    }

    func incrementProgress(for planLine: PlanLine) {
        guard let updatedDraftProgressState = WorkoutTextProgressUpdater.incrementProgress(
            for: planLine.id,
            in: parsedText,
            draftProgress: draftProgressState
        ) else {
            return
        }

        draftProgressState = updatedDraftProgressState
        progressRecoveryContext = DraftProgressRecoveryContext(
            parseResult: parsedText,
            draftProgressState: updatedDraftProgressState
        )
        persistImmediately()
    }

    func finishWorkout() {
        cancelPendingPersistence()

        let finalizedText = WorkoutTextProgressUpdater.finalizeWorkout(
            in: parsedText,
            draftProgress: draftProgressState
        )

        draftProgressState = WorkoutDraftProgressState()
        parsedText = WorkoutTextParser.parse(
            rawText: finalizedText,
            reconcilingWith: parsedText.snapshot
        )
        noteText = finalizedText
        progressRecoveryContext = nil

        persistImmediately()
    }

    func flushPendingPersistence() {
        cancelPendingPersistence()
        persistIfNeeded()
    }

    private func scheduleDebouncedPersistence() {
        hasPendingPersistence = true
        cancelPendingPersistence()

        guard workoutNote != nil, saveAction != nil else {
            return
        }

        let saveDebounceNanoseconds = saveDebounceNanoseconds
        pendingPersistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: saveDebounceNanoseconds)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.persistIfNeeded()
        }
    }

    private func persistImmediately() {
        hasPendingPersistence = true
        flushPendingPersistence()
    }

    private func cancelPendingPersistence() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
    }

    private func applyCommittedParseState(for rawText: String) {
        let currentParseResult = parsedText
        let currentDraftProgressState = draftProgressState
        let reconciledSnapshot = WorkoutTextSnapshot(
            rawText: rawText,
            reconcilingWith: currentParseResult.snapshot
        )
        let immediateNextParseResult = WorkoutTextParser.parse(snapshot: reconciledSnapshot)
        let immediateNextDraftProgressState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            nextParseResult: immediateNextParseResult,
            previousParseResult: currentParseResult,
            previousDraftProgress: currentDraftProgressState
        )

        if
            currentDraftProgressState.isEmpty == false,
            immediateNextDraftProgressState.entries.count < currentDraftProgressState.entries.count
        {
            progressRecoveryContext = DraftProgressRecoveryContext(
                parseResult: currentParseResult,
                draftProgressState: currentDraftProgressState
            )
        }

        var resolvedParseResult = immediateNextParseResult
        var resolvedDraftProgressState = immediateNextDraftProgressState

        if
            let recoveredState = recoveredDraftProgressState(for: rawText),
            recoveredState.draftProgressState.entries.count > resolvedDraftProgressState.entries.count
        {
            resolvedParseResult = recoveredState.parseResult
            resolvedDraftProgressState = recoveredState.draftProgressState
        }

        parsedText = resolvedParseResult
        draftProgressState = resolvedDraftProgressState
        progressRecoveryContext = resolvedDraftProgressState.isEmpty
            ? progressRecoveryContext
            : DraftProgressRecoveryContext(
                parseResult: resolvedParseResult,
                draftProgressState: resolvedDraftProgressState
            )
    }

    private func recoveredDraftProgressState(
        for rawText: String
    ) -> DraftProgressRecoveryContext? {
        guard let progressRecoveryContext else {
            return nil
        }

        let recoveredSnapshot = WorkoutTextSnapshot(
            rawText: rawText,
            reconcilingWith: progressRecoveryContext.parseResult.snapshot
        )
        let recoveredParseResult = WorkoutTextParser.parse(snapshot: recoveredSnapshot)
        let recoveredDraftProgressState = WorkoutTextProgressUpdater.reconcileDraftProgress(
            nextParseResult: recoveredParseResult,
            previousParseResult: progressRecoveryContext.parseResult,
            previousDraftProgress: progressRecoveryContext.draftProgressState
        )

        guard recoveredDraftProgressState.isEmpty == false else {
            return nil
        }

        return DraftProgressRecoveryContext(
            parseResult: recoveredParseResult,
            draftProgressState: recoveredDraftProgressState
        )
    }

    private func persistIfNeeded() {
        guard
            hasPendingPersistence,
            let workoutNote,
            let saveAction
        else {
            return
        }

        do {
            try saveAction(workoutNote, currentPersistedState)
            hasPendingPersistence = false
            lastPersistenceErrorMessage = nil
        } catch {
            let message = "Failed to persist workout draft: \(error.localizedDescription)"
            lastPersistenceErrorMessage = message
            QuickRepDiagnostics.log(message)
        }
    }

    private var currentPersistedState: PersistedState {
        PersistedState(
            rawText: noteText,
            draftProgressState: draftProgressState
        )
    }
}
