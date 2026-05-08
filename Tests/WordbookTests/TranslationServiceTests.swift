import Foundation
import XCTest
@testable import Wordbook

final class TranslationServiceTests: XCTestCase {
    func testMyMemorySuccessResponseParsesTranslatedText() async throws {
        let data = """
        {
          "responseData": { "translatedText": "你好" },
          "responseStatus": 200,
          "responseDetails": ""
        }
        """.data(using: .utf8)!
        let service = MyMemoryTranslationService(
            emailProvider: { nil },
            dataLoader: { url in
                XCTAssertTrue(url.absoluteString.contains("langpair=en%7Czh-CN"))
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        let translated = try await service.translate("hello", from: .english, to: .chinese)
        XCTAssertEqual(translated, "你好")
    }

    func testMyMemoryEmptyResultThrows() async {
        let data = """
        {
          "responseData": { "translatedText": "" },
          "responseStatus": 200,
          "responseDetails": ""
        }
        """.data(using: .utf8)!
        let service = MyMemoryTranslationService(
            emailProvider: { nil },
            dataLoader: { url in
                (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        do {
            _ = try await service.translate("hello", from: .english, to: .chinese)
            XCTFail("Expected empty translation to throw")
        } catch TranslationServiceError.emptyTranslation {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMyMemoryServerMessageThrows() async {
        let data = """
        {
          "responseData": { "translatedText": "" },
          "responseStatus": 429,
          "responseDetails": "quota exceeded"
        }
        """.data(using: .utf8)!
        let service = MyMemoryTranslationService(
            emailProvider: { nil },
            dataLoader: { url in
                (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        )

        do {
            _ = try await service.translate("hello", from: .english, to: .chinese)
            XCTFail("Expected server message to throw")
        } catch TranslationServiceError.serverMessage(let message) {
            XCTAssertEqual(message, "quota exceeded")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
