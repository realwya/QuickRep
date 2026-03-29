import Foundation

enum ExerciseLibraryCatalog {
    static let builtinExerciseNames: [String] = [
        "卧推",
        "深蹲",
        "硬拉",
        "肩推",
        "引体向上",
        "杠铃划船",
    ]

    static func builtinEntries() -> [ExerciseLibraryEntry] {
        builtinExerciseNames.map { name in
            ExerciseLibraryEntry(name: name, isBuiltin: true)
        }
    }
}
