import Foundation

enum TranslationLanguage: String {
    case english = "en"
    case chinese = "zh-CN"
}

protocol TranslationServicing {
    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String
    func batchTranslate(_ texts: [String], from source: TranslationLanguage, to target: TranslationLanguage) async throws -> [String]
}

extension TranslationServicing {
    func batchTranslate(_ texts: [String], from source: TranslationLanguage, to target: TranslationLanguage) async throws -> [String] {
        var results: [String] = []
        for text in texts {
            let result = try await translate(text, from: source, to: target)
            results.append(result)
        }
        return results
    }
}

enum TranslationServiceError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyTranslation
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "翻译服务地址无效"
        case .invalidResponse:
            return "翻译服务返回异常"
        case .emptyTranslation:
            return "翻译服务没有返回结果"
        case let .serverMessage(message):
            return message
        }
    }
}

struct MyMemoryTranslationService: TranslationServicing {
    var emailProvider: @Sendable () -> String? = {
        UserDefaults.standard.string(forKey: .myMemoryContactEmail)
    }
    var dataLoader: @Sendable (URL) async throws -> (Data, URLResponse) = { url in
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return try await URLSession(configuration: config).data(from: url)
    }

    private static let batchSeparator = " \u{FF5C}\u{FF5C} "

    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        try await requestTranslation(text: text, source: source, to: target)
    }

    func batchTranslate(_ texts: [String], from source: TranslationLanguage, to target: TranslationLanguage) async throws -> [String] {
        let nonEmptyTexts = texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyTexts.isEmpty else { return texts.map { _ in "" } }
        guard nonEmptyTexts.count > 1 else {
            let single = try await translate(nonEmptyTexts[0], from: source, to: target)
            return texts.map { $0.isEmpty ? "" : single }
        }

        let joined = nonEmptyTexts.joined(separator: Self.batchSeparator)
        let translated = try await requestTranslation(text: joined, source: source, to: target)
        let parts = translated.components(separatedBy: "\u{FF5C}\u{FF5C}")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var result: [String] = []
        var textIndex = 0
        for originalText in texts {
            if originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append("")
            } else if textIndex < parts.count {
                result.append(parts[textIndex])
                textIndex += 1
            } else {
                result.append(originalText)
            }
        }
        return result
    }

    private var myMemoryBaseURL: String {
        UserDefaults.standard.string(forKey: .myMemoryAPIBaseURL) ?? "https://api.mymemory.translated.net/get"
    }

    private func requestTranslation(text: String, source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        var components = URLComponents(string: myMemoryBaseURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(source.rawValue)|\(target.rawValue)")
        ]
        if let email = emailProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "de", value: email))
        }

        guard let url = components?.url else { throw TranslationServiceError.invalidURL }
        let (data, response) = try await dataLoader(url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        if let message = payload.responseDetails, payload.responseStatus != 200 {
            throw TranslationServiceError.serverMessage(message)
        }

        let translated = payload.responseData.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw TranslationServiceError.emptyTranslation }
        return translated
    }
}

private struct MyMemoryResponse: Decodable {
    struct ResponseData: Decodable {
        let translatedText: String
    }

    let responseData: ResponseData
    let responseStatus: Int?
    let responseDetails: String?
}

// MARK: - Translation Result

enum TranslationConfidence: String {
    case high = "高置信"
    case medium = "单源"
    case low = "低置信"
}

struct TranslationResult {
    let text: String
    let sourceName: String
    let confidence: TranslationConfidence
}

// MARK: - Lingva

struct LingvaTranslationService: TranslationServicing {
    var dataLoader: @Sendable (URL) async throws -> (Data, URLResponse) = { url in
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return try await URLSession(configuration: config).data(from: url)
    }

    var baseURL: String {
        UserDefaults.standard.string(forKey: .lingvaAPIBaseURL) ?? "https://lingva.marginalia.nu/api/v1"
    }

    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        guard let url = URL(string: "\(baseURL)/\(source.rawValue)/\(target.rawValue)/\(encoded)") else {
            throw TranslationServiceError.invalidURL
        }
        let (data, response) = try await dataLoader(url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(LingvaResponse.self, from: data)
        let result = payload.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationServiceError.emptyTranslation }
        return result
    }
}

private struct LingvaResponse: Decodable {
    let translation: String
}

// MARK: - LibreTranslate

struct LibreTranslateTranslationService: TranslationServicing {
    var baseURL: String {
        UserDefaults.standard.string(forKey: .libreTranslateBaseURL) ?? "https://libretranslate.com"
    }
    var apiKey: String? {
        if let key = UserDefaults.standard.string(forKey: .libreTranslateAPIKey), !key.isEmpty { return key }
        return nil
    }
    var dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return try await URLSession(configuration: config).data(for: request)
    }

    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        guard let url = URL(string: "\(baseURL)/translate") else {
            throw TranslationServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "q": text,
            "source": source.rawValue,
            "target": target.rawValue,
            "format": "text"
        ]
        if let apiKey { body["api_key"] = apiKey }

        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(LibreTranslateResponse.self, from: data)
        let result = payload.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationServiceError.emptyTranslation }
        return result
    }
}

private struct LibreTranslateResponse: Decodable {
    let translatedText: String
}

// MARK: - Composite Translation

struct CompositeTranslationService: TranslationServicing {
    struct NamedService {
        let name: String
        let service: TranslationServicing
    }

    let services: [NamedService]
    let perServiceTimeout: TimeInterval

    init(services: [NamedService], perServiceTimeout: TimeInterval = 8) {
        self.services = services
        self.perServiceTimeout = perServiceTimeout
    }

    static let `default` = CompositeTranslationService(services: [
        NamedService(name: "MyMemory", service: MyMemoryTranslationService()),
        NamedService(name: "Lingva", service: LingvaTranslationService()),
        NamedService(name: "LibreTranslate", service: LibreTranslateTranslationService()),
    ])

    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        let result = try await translateWithConfidence(text, from: source, to: target)
        return result.text
    }

    func translateWithConfidence(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> TranslationResult {
        guard !services.isEmpty else { throw TranslationServiceError.emptyTranslation }

        let results = await withTaskGroup(of: (String, String)?.self) { group in
            for named in services {
                group.addTask {
                    do {
                        let translated = try await withTimeout(perServiceTimeout) {
                            try await named.service.translate(text, from: source, to: target)
                        }
                        return (named.name, translated)
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [(String, String)] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        guard !results.isEmpty else { throw TranslationServiceError.emptyTranslation }

        // 规范化比较，判断多源一致性
        let normalizedResults = results.map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        let uniqueValues = Set(normalizedResults.map { $0.1 })

        let confidence: TranslationConfidence
        if uniqueValues.count >= 2 && results.count >= 2 {
            // 检查是否有至少2个相同的结果
            let mostCommon = mostFrequentValue(in: normalizedResults.map { $0.1 })
            if mostCommon.count >= 2 {
                confidence = .high
                // 返回最一致的翻译原文
                let winner = results.first { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == mostCommon.value }!
                return TranslationResult(text: winner.1, sourceName: "\(results.count)源一致", confidence: confidence)
            }
            confidence = .medium
        } else if results.count >= 2 {
            confidence = .high
        } else {
            confidence = .medium
        }

        let first = results.first!
        return TranslationResult(text: first.1, sourceName: first.0, confidence: confidence)
    }

    private func mostFrequentValue(in values: [String]) -> (value: String, count: Int) {
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value }) ?? (values[0], 1)
    }

    func batchTranslate(_ texts: [String], from source: TranslationLanguage, to target: TranslationLanguage) async throws -> [String] {
        // 复合服务回退到 MyMemory 的批量模式
        let myMemory = MyMemoryTranslationService()
        return try await myMemory.batchTranslate(texts, from: source, to: target)
    }
}

private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TranslationServiceError.serverMessage("timeout")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
