import Foundation

struct ExerciseAutocompleteSuggestion: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let isBuiltin: Bool
}

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

    static func autocompleteSuggestions(
        matching query: String,
        from entries: [ExerciseLibraryEntry],
        limit: Int = 6
    ) -> [ExerciseAutocompleteSuggestion] {
        let normalizedQuery = normalize(query)
        let deduplicatedSuggestions = Dictionary(
            entries.map {
                (
                    normalize($0.name),
                    ExerciseAutocompleteSuggestion(
                        name: $0.name,
                        isBuiltin: $0.isBuiltin
                    )
                )
            },
            uniquingKeysWith: { existing, incoming in
                existing.isBuiltin ? existing : incoming
            }
        )
        .values

        let suggestions = deduplicatedSuggestions
            .filter { suggestion in
                normalizedQuery.isEmpty || normalize(suggestion.name).contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                sortKey(for: lhs, query: normalizedQuery) < sortKey(for: rhs, query: normalizedQuery)
            }

        if
            normalizedQuery.isEmpty == false,
            suggestions.contains(where: { normalize($0.name) == normalizedQuery })
        {
            return []
        }

        return Array(suggestions.prefix(limit))
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func sortKey(
        for suggestion: ExerciseAutocompleteSuggestion,
        query: String
    ) -> (Int, Int, String) {
        let normalizedName = normalize(suggestion.name)
        let prefixRank = query.isEmpty || normalizedName.hasPrefix(query) ? 0 : 1
        let sourceRank = suggestion.isBuiltin ? 0 : 1
        return (prefixRank, sourceRank, normalizedName)
    }
}
