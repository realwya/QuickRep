import Foundation

struct ExerciseAutocompleteSuggestion: Identifiable, Hashable {
    var id: String { name }

    let name: String
    let isBuiltin: Bool
}

enum ExerciseLibraryCatalog {
    private struct ExerciseSearchIndex {
        let normalizedName: String
        let compactName: String
        let fullPinyin: String
        let initials: String
    }

    private struct MatchedSuggestion {
        let suggestion: ExerciseAutocompleteSuggestion
        let searchIndex: ExerciseSearchIndex
        let matchRank: Int
    }

    static let builtinExerciseNames: [String] = [
        "卧推",
        "深蹲",
        "硬拉",
        "肩推",
        "引体向上",
        "杠铃划船",
        "保加利亚分腿蹲",
        "单腿罗马尼亚硬拉",
        "壶铃摇摆",
        "高翻"
    ]

    static func builtinEntries() -> [ExerciseLibraryEntry] {
        builtinExerciseNames.map { name in
            ExerciseLibraryEntry(name: name, isBuiltin: true)
        }
    }

    static func autocompleteSuggestions(
        matching query: String,
        from entries: [ExerciseLibraryEntry]
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
            .compactMap { suggestion -> MatchedSuggestion? in
                let searchIndex = searchIndex(for: suggestion.name)

                guard let matchRank = matchRank(for: searchIndex, query: normalizedQuery) else {
                    return nil
                }

                return MatchedSuggestion(
                    suggestion: suggestion,
                    searchIndex: searchIndex,
                    matchRank: matchRank
                )
            }
            .sorted { lhs, rhs in
                sortKey(for: lhs) < sortKey(for: rhs)
            }

        if
            normalizedQuery.isEmpty == false,
            suggestions.contains(where: { $0.searchIndex.normalizedName == normalizedQuery })
        {
            return []
        }

        return suggestions.map(\.suggestion)
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func sortKey(
        for matchedSuggestion: MatchedSuggestion
    ) -> (Int, Int, Int, String) {
        let sourceRank = matchedSuggestion.suggestion.isBuiltin ? 0 : 1
        return (
            matchedSuggestion.matchRank,
            sourceRank,
            matchedSuggestion.searchIndex.normalizedName.count,
            matchedSuggestion.searchIndex.normalizedName
        )
    }

    private static func matchRank(
        for searchIndex: ExerciseSearchIndex,
        query: String
    ) -> Int? {
        guard query.isEmpty == false else {
            return 0
        }

        guard shouldUseLatinMatching(for: query) else {
            if searchIndex.normalizedName.hasPrefix(query) {
                return 0
            }

            if searchIndex.normalizedName.contains(query) {
                return 1
            }

            return nil
        }

        let compactQuery = compactSearchKey(query)

        if searchIndex.normalizedName.hasPrefix(query) {
            return 0
        }

        if searchIndex.compactName.hasPrefix(compactQuery) {
            return 1
        }

        if searchIndex.fullPinyin.hasPrefix(compactQuery) {
            return 2
        }

        if searchIndex.initials.hasPrefix(compactQuery) {
            return 3
        }

        if searchIndex.normalizedName.contains(query) {
            return 4
        }

        if searchIndex.compactName.contains(compactQuery) {
            return 5
        }

        if searchIndex.fullPinyin.contains(compactQuery) {
            return 6
        }

        if searchIndex.initials.contains(compactQuery) {
            return 7
        }

        return nil
    }

    private static func searchIndex(for name: String) -> ExerciseSearchIndex {
        let normalizedName = normalize(name)
        let compactName = compactSearchKey(normalizedName)
        let pinyinTokens = pinyinTokens(for: normalizedName)

        return ExerciseSearchIndex(
            normalizedName: normalizedName,
            compactName: compactName,
            fullPinyin: pinyinTokens.joined(),
            initials: pinyinTokens.compactMap(\.first).map(String.init).joined()
        )
    }

    private static func shouldUseLatinMatching(for query: String) -> Bool {
        let meaningfulScalars = query.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }

        guard meaningfulScalars.isEmpty == false else {
            return false
        }

        return meaningfulScalars.allSatisfy(\.isASCII)
    }

    private static func compactSearchKey(_ text: String) -> String {
        let normalizedText = normalize(text)

        return String(
            String.UnicodeScalarView(
                normalizedText.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            )
        )
    }

    private static func pinyinTokens(for text: String) -> [String] {
        guard let latinText = text.applyingTransform(.toLatin, reverse: false) else {
            return []
        }

        return latinText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }
}
