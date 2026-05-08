import Foundation

struct DictionaryLookupEntry: Hashable {
    var word: String
    var phonetic: String?
    var meanings: [DictionaryLookupMeaning]
}

struct DictionaryLookupMeaning: Hashable {
    var partOfSpeech: String
    var definitions: [DictionaryLookupDefinition]
}

struct DictionaryLookupDefinition: Hashable {
    var definition: String
    var example: String?
    var synonyms: [String]
}

protocol DictionaryLookupServicing {
    func lookup(word: String) async throws -> DictionaryLookupEntry
}

enum DictionaryLookupError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case notFound
    case emptyResult
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "词典服务地址无效"
        case .invalidResponse:
            return "词典服务返回异常"
        case .notFound:
            return "词典里暂时没找到这个词"
        case .emptyResult:
            return "词典没有返回可用释义"
        case let .serverMessage(message):
            return message
        }
    }
}

struct FreeDictionaryLookupService: DictionaryLookupServicing {
    var dataLoader: @Sendable (URL) async throws -> (Data, URLResponse) = { url in
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return try await URLSession(configuration: config).data(from: url)
    }

    var baseURL: String {
        UserDefaults.standard.string(forKey: .dictionaryAPIBaseURL) ?? "https://api.dictionaryapi.dev/api/v2/entries/en"
    }

    func lookup(word: String) async throws -> DictionaryLookupEntry {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw DictionaryLookupError.emptyResult }

        let encodedWord = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
        guard let url = URL(string: "\(baseURL)/\(encodedWord)") else {
            throw DictionaryLookupError.invalidURL
        }

        return try await withNetworkRetry {
            try await performLookup(url: url, normalized: normalized)
        }
    }

    private func performLookup(url: URL, normalized: String) async throws -> DictionaryLookupEntry {
        let (data, response) = try await dataLoader(url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictionaryLookupError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            if let payload = try? JSONDecoder().decode(FreeDictionaryErrorResponse.self, from: data),
               let message = nonEmpty(payload.message) {
                throw DictionaryLookupError.serverMessage(message)
            }
            throw DictionaryLookupError.notFound
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DictionaryLookupError.invalidResponse
        }

        let payload = try JSONDecoder().decode([FreeDictionaryEntryResponse].self, from: data)
        guard let first = payload.first else { throw DictionaryLookupError.emptyResult }

        let phonetic = nonEmpty(first.phonetic) ?? first.phonetics.compactMap { nonEmpty($0.text) }.first
        let meanings = first.meanings.compactMap { meaning -> DictionaryLookupMeaning? in
            let definitions = meaning.definitions.compactMap { definition -> DictionaryLookupDefinition? in
                let text = definition.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DictionaryLookupDefinition(
                    definition: text,
                    example: nonEmpty(definition.example),
                    synonyms: Array(definition.synonyms.prefix(6))
                )
            }
            guard !definitions.isEmpty else { return nil }
            return DictionaryLookupMeaning(partOfSpeech: meaning.partOfSpeech, definitions: definitions)
        }

        guard !meanings.isEmpty else { throw DictionaryLookupError.emptyResult }

        return DictionaryLookupEntry(
            word: nonEmpty(first.word) ?? normalized,
            phonetic: phonetic,
            meanings: meanings
        )
    }
}

private func withNetworkRetry<T>(maxAttempts: Int = 3, operation: @escaping () async throws -> T) async throws -> T {
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch {
            guard error is URLError, attempt < maxAttempts - 1 else { throw error }
            try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
        }
    }
    fatalError("unreachable")
}

private struct FreeDictionaryEntryResponse: Decodable {
    struct Phonetic: Decodable {
        let text: String?
    }

    struct Meaning: Decodable {
        struct Definition: Decodable {
            let definition: String
            let example: String?
            let synonyms: [String]
        }

        let partOfSpeech: String
        let definitions: [Definition]
    }

    let word: String
    let phonetic: String?
    let phonetics: [Phonetic]
    let meanings: [Meaning]
}

private struct FreeDictionaryErrorResponse: Decodable {
    let message: String?
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
