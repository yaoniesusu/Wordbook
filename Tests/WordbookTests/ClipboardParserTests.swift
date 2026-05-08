import XCTest
@testable import Wordbook

final class ClipboardParserTests: XCTestCase {
    func testParseTabSeparatedContent() {
        let parsed = ClipboardParser.parseBobStyle("hello\t你好")
        XCTAssertEqual(parsed.english, "hello")
        XCTAssertEqual(parsed.chinese, "你好")
        XCTAssertEqual(parsed.example, "")
    }

    func testParseChineseFirstTabSeparatedContent() {
        let parsed = ClipboardParser.parseBobStyle("你好\thello")
        XCTAssertEqual(parsed.english, "hello")
        XCTAssertEqual(parsed.chinese, "你好")
        XCTAssertEqual(parsed.example, "")
    }

    func testParseDashSeparatedContent() {
        let parsed = ClipboardParser.parseBobStyle("take off - 起飞")
        XCTAssertEqual(parsed.english, "take off")
        XCTAssertEqual(parsed.chinese, "起飞")
    }

    func testParseChineseFirstDashSeparatedContent() {
        let parsed = ClipboardParser.parseBobStyle("起飞 - take off")
        XCTAssertEqual(parsed.english, "take off")
        XCTAssertEqual(parsed.chinese, "起飞")
    }

    func testParseMultilineContentWithExample() {
        let parsed = ClipboardParser.parseBobStyle(
            """
            despite
            尽管
            Despite the rain, we went out.
            """
        )
        XCTAssertEqual(parsed.english, "despite")
        XCTAssertEqual(parsed.chinese, "尽管")
        XCTAssertEqual(parsed.example, "Despite the rain, we went out.")
    }

    func testParseChineseFirstMultilineContentWithExample() {
        let parsed = ClipboardParser.parseBobStyle(
            """
            尽管
            despite
            Despite the rain, we went out.
            """
        )
        XCTAssertEqual(parsed.english, "despite")
        XCTAssertEqual(parsed.chinese, "尽管")
        XCTAssertEqual(parsed.example, "Despite the rain, we went out.")
    }

    func testShouldRejectSingleURL() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("https://example.com"))
    }

    func testShouldRejectOverlongText() {
        let longText = String(repeating: "a", count: 4001)
        XCTAssertFalse(ClipboardParser.shouldAutoIngest(longText))
    }

    func testShouldAcceptPureChineseText() {
        XCTAssertTrue(ClipboardParser.shouldAutoIngest("纯中文内容"))
    }

    func testShouldAcceptPureEnglishText() {
        XCTAssertTrue(ClipboardParser.shouldAutoIngest("hello"))
    }

    func testShouldAcceptCapitalizedSingleWord() {
        XCTAssertTrue(ClipboardParser.shouldAutoIngest("Resilient"))
    }

    func testShouldAcceptHyphenatedVocabulary() {
        XCTAssertTrue(ClipboardParser.shouldAutoIngest("state-of-the-art"))
    }

    func testShouldAcceptChineseFirstBilingualText() {
        XCTAssertTrue(ClipboardParser.shouldAutoIngest("纯中文内容\tChinese text"))
    }

    func testShouldRejectGarbledReplacementCharacter() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("hello\u{FFFD}world"))
    }

    func testShouldRejectPrivateUseAreaText() {
        let garbled = String(repeating: "\u{E000}\u{E001}\u{E002}", count: 5)
        XCTAssertFalse(ClipboardParser.shouldAutoIngest(garbled))
    }

    func testShouldRejectPurePunctuation() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("!!@@##$$%%^^&&**(()))__++"))
    }

    func testShouldRejectParagraphExceeding15Words() {
        let paragraph = String(repeating: "word ", count: 20)
        XCTAssertFalse(ClipboardParser.shouldAutoIngest(paragraph))
    }

    func testShouldRejectEmbeddedURL() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("check https://example.com for details"))
    }

    func testShouldRejectEmail() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("user@example.com"))
    }

    func testShouldRejectUUID() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("550e8400-e29b-41d4-a716-446655440000"))
    }

    func testShouldRejectFilePath() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("/usr/local/bin/wordbook"))
    }

    func testShouldRejectVersionNumber() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("v1.2.3-beta.1"))
    }

    func testShouldRejectPureNumberID() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("20240507001234"))
    }

    func testShouldRejectKeyboardSmash() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("asdf qwer zxcv"))
    }

    func testShouldRejectRepeatedChar() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("aaaaaaaa"))
    }

    func testShouldRejectPureSymbols() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("--- === ***"))
    }

    func testShouldRejectMagnetLink() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("magnet:?xt=urn:btih:ABCDEF1234567890ABCDEF1234567890ABCDEF12"))
    }

    func testShouldRejectSocialHandle() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("@username check this out"))
    }

    func testShouldRejectHashtag() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("#swiftui #macos"))
    }

    func testShouldRejectJWToken() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNq5iW"))
    }

    func testShouldRejectSSHKey() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("-----BEGIN RSA PRIVATE KEY-----"))
    }

    func testShouldRejectHTMLTag() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("<div class=\"word\">hello</div>"))
    }

    func testShouldRejectJavaScriptCode() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("const word = 'hello';"))
    }

    func testShouldRejectJSON() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("{\"word\":\"hello\"}"))
    }

    func testShouldRejectSerialKey() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("ABCD-EFGH-IJKL-MNOP"))
    }

    func testShouldRejectAdultCatalogNumbers() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("ABP-123"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("SSIS 001"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("mukd455"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("FC2-PPV-1234567"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("HEYZO-1234"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("1PON-123456_001"))
    }

    func testShouldRejectPersonName() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("John Smith"))
    }

    func testShouldRejectCurrency() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("$1,234.56"))
    }

    func testShouldRejectPureDate() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("2024-01-15"))
    }

    func testShouldRejectMarkdownLink() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("[click here](https://example.com)"))
    }

    func testShouldRejectBareDomain() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("www.example.dev/docs"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("example.com"))
    }

    func testShouldRejectRelativeSourcePathAndLineNumber() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("Sources/Wordbook/Views/ContentView.swift"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("ContentView.swift:42"))
    }

    func testShouldRejectCodeIdentifiers() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("clipboard_auto_capture"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("defaultClipboardSource"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("UserDefaultsKey.clipboardAutoCaptureEnabled"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("getUserName()"))
    }

    func testShouldRejectShellCommandsAndMenuPaths() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("$ swift test"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("git status"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("Edit > Copy"))
    }

    func testShouldRejectStatusCodesAndTicketIDs() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("ERR_CONNECTION_REFUSED"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("HTTP 404"))
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("Issue #12345"))
    }

    func testShouldRejectBundleIdentifier() {
        XCTAssertFalse(ClipboardParser.shouldAutoIngest("com.apple.Safari"))
    }
}
