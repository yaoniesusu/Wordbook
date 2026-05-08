import XCTest
@testable import Wordbook

final class DictionaryLookupServiceTests: XCTestCase {
    func testDictionaryLookupParsesMeaningsAndPhonetic() async throws {
        let payload = """
        [
          {
            "word": "hello",
            "phonetic": "həˈləʊ",
            "phonetics": [{"text": "həˈləʊ"}],
            "meanings": [
              {
                "partOfSpeech": "noun",
                "definitions": [
                  {
                    "definition": "a greeting",
                    "example": "hello there",
                    "synonyms": ["hi"]
                  }
                ]
              }
            ]
          }
        ]
        """.data(using: .utf8)!

        let service = FreeDictionaryLookupService { _ in
            (payload, HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let entry = try await service.lookup(word: "hello")
        XCTAssertEqual(entry.word, "hello")
        XCTAssertEqual(entry.phonetic, "həˈləʊ")
        XCTAssertEqual(entry.meanings.first?.partOfSpeech, "noun")
        XCTAssertEqual(entry.meanings.first?.definitions.first?.definition, "a greeting")
    }

    func testDictionaryLookupNotFoundSurfaceMessage() async {
        let payload = """
        {
          "message": "No Definitions Found"
        }
        """.data(using: .utf8)!

        let service = FreeDictionaryLookupService { _ in
            (payload, HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await service.lookup(word: "zzzz")
            XCTFail("Expected not found error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No Definitions Found"))
        }
    }
}
