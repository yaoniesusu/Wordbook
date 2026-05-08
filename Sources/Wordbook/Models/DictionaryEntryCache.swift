import Foundation

struct DictionaryEntryCache: Codable, Hashable {
    var word: String
    var phonetic: String?
    var meanings: [DictionaryMeaningCache]
    var fetchedAt: Date

    var summaryChinese: String? {
        meanings
            .flatMap(\.definitions)
            .compactMap { definition in
                let trimmed = definition.chineseDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
    }
}

struct DictionaryMeaningCache: Codable, Hashable, Identifiable {
    var id: String { partOfSpeech + "-" + definitions.map(\.englishDefinition).joined(separator: "|") }
    var partOfSpeech: String
    var definitions: [DictionarySense]
}

struct DictionarySense: Codable, Hashable, Identifiable {
    var id: String { englishDefinition + "-" + (example ?? "") }
    var englishDefinition: String
    var chineseDefinition: String
    var example: String?
    var translatedExample: String?
    var synonyms: [String]
}
