import Foundation
import SwiftData

@Model
final class WorkoutNote {
    @Attribute(.unique) var id: UUID

    // `rawText` is the only persisted source of truth for a workout note.
    // Parsed exercise blocks, plan lines, and in-progress set counts must be
    // rebuilt from this text instead of being stored separately.
    var rawText: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        rawText: String = "",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.updatedAt = updatedAt
    }

    func textSnapshot(
        reconcilingWith previous: WorkoutTextSnapshot? = nil
    ) -> WorkoutTextSnapshot {
        // The runtime line snapshot is always rebuilt from rawText rather than
        // stored separately, so rawText remains the only persisted source.
        WorkoutTextSnapshot(
            rawText: rawText,
            reconcilingWith: previous
        )
    }
}
