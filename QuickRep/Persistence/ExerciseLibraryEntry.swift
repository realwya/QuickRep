import Foundation
import SwiftData

@Model
final class ExerciseLibraryEntry {
    @Attribute(.unique) var id: UUID
    var name: String
    var isBuiltin: Bool

    init(
        id: UUID = UUID(),
        name: String,
        isBuiltin: Bool
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
    }
}
