import Foundation
import SwiftData

@Model
final class WorkoutNote {
    @Attribute(.unique) var id: UUID

    // `rawText` stores the editable workout content and finalized workout
    // result. In-flight plan progress is persisted separately until the workout
    // is explicitly finished.
    var rawText: String
    var draftProgressData: Data?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        rawText: String = "",
        draftProgressData: Data? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.draftProgressData = draftProgressData
        self.updatedAt = updatedAt
    }

    var draftProgressState: WorkoutDraftProgressState {
        get {
            Self.decodedDraftProgressState(from: draftProgressData)
        }
        set {
            do {
                draftProgressData = try Self.encodedDraftProgressData(from: newValue)
            } catch {
                GymlogDiagnostics.log(
                    "Failed to encode workout draft progress for note \(id): \(error.localizedDescription)"
                )
            }
        }
    }

    func textSnapshot(
        reconcilingWith previous: WorkoutTextSnapshot? = nil
    ) -> WorkoutTextSnapshot {
        WorkoutTextSnapshot(
            rawText: rawText,
            reconcilingWith: previous
        )
    }

    func parsedText(
        reconcilingWith previous: WorkoutTextSnapshot? = nil
    ) -> WorkoutTextParseResult {
        WorkoutTextParser.parse(
            rawText: rawText,
            reconcilingWith: previous
        )
    }

    func applyEditorState(
        rawText: String,
        draftProgressState: WorkoutDraftProgressState,
        updatedAt: Date = .now
    ) throws {
        self.rawText = rawText
        self.draftProgressData = try Self.encodedDraftProgressData(from: draftProgressState)
        self.updatedAt = updatedAt
    }

    static func decodedDraftProgressState(from data: Data?) -> WorkoutDraftProgressState {
        guard let data else {
            return WorkoutDraftProgressState()
        }

        do {
            return try JSONDecoder().decode(
                WorkoutDraftProgressState.self,
                from: data
            )
        } catch {
            GymlogDiagnostics.log(
                "Failed to decode workout draft progress: \(error.localizedDescription)"
            )
            return WorkoutDraftProgressState()
        }
    }

    static func encodedDraftProgressData(
        from state: WorkoutDraftProgressState
    ) throws -> Data? {
        guard !state.isEmpty else {
            return nil
        }

        return try JSONEncoder().encode(state)
    }
}

@Model
final class WorkoutHistoryRecord {
    @Attribute(.unique) var id: UUID
    var rawText: String
    var finishedAt: Date

    init(
        id: UUID = UUID(),
        rawText: String,
        finishedAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.finishedAt = finishedAt
    }
}

enum TrainingHistoryStore {
    @MainActor
    static func recordFinishedWorkout(
        finalizedRawText: String,
        draftWorkoutNote: WorkoutNote?,
        modelContext: ModelContext,
        finishedAt: Date = .now
    ) throws {
        if finalizedRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            modelContext.insert(
                WorkoutHistoryRecord(
                    rawText: finalizedRawText,
                    finishedAt: finishedAt
                )
            )
        }

        let draftNote = draftWorkoutNote
            ?? latestWorkoutNote(in: modelContext)
            ?? {
                let note = WorkoutNote(rawText: "")
                modelContext.insert(note)
                return note
            }()

        try draftNote.applyEditorState(
            rawText: "",
            draftProgressState: WorkoutDraftProgressState(),
            updatedAt: finishedAt
        )
        try modelContext.save()
    }

    @MainActor
    private static func latestWorkoutNote(in modelContext: ModelContext) -> WorkoutNote? {
        let descriptor = FetchDescriptor<WorkoutNote>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }
}
