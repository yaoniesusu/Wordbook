import Foundation
import XCTest
@testable import Wordbook

@MainActor
final class WordbookStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testLoadEmptyDirectoryStartsWithNoEntries() {
        let store = testStore()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testStorageLocationResolverDefaultsToApplicationSupportWordbookDirectory() {
        let directory = StorageLocationResolver().wordbookDirectory()

        XCTAssertEqual(directory.lastPathComponent, "Wordbook")
        XCTAssertTrue(directory.path.contains("Application Support"))
    }

    func testInjectedPasteboardReaderSupportsManualClipboardAdd() async {
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "portable\t可移植的" },
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "portable")
        XCTAssertEqual(store.entries.first?.chinese, "可移植的")
    }

    func testClipboardAutoCaptureCapabilityMatchesCurrentPlatform() {
        #if os(macOS)
        XCTAssertTrue(PlatformFeatures.supportsClipboardAutoCapture)
        #else
        XCTAssertFalse(PlatformFeatures.supportsClipboardAutoCapture)
        #endif
    }

    func testSaveAndReloadPersistsEntries() {
        let store = testStore()
        store.addManualEntry(
            english: "resilient",
            chinese: "有韧性的",
            exampleSentence: "A resilient system recovers quickly.",
            tags: ["tech"],
            source: "manual"
        )

        let reloaded = testStore()
        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.english, "resilient")
        XCTAssertEqual(reloaded.entries.first?.reviewCount, 0)
    }

    func testDuplicateClipboardCaptureMergesIntoExistingEntry() async {
        var clipboardText = "focus\t专注"
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { clipboardText },
            saveDelay: 0
        )

        await store.addFromClipboardAndWait(mergeTags: ["work"], sourceHint: "Bob", autoCaptured: true)
        clipboardText = "focus\t聚焦"
        await store.addFromClipboardAndWait(mergeTags: ["study"], sourceHint: "Bob", autoCaptured: true)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.chinese, "专注")
        XCTAssertEqual(store.entries.first?.tags.sorted(), ["study", "work"])
        XCTAssertEqual(store.automaticIngestHistory.count, 2)
        XCTAssertEqual(store.automaticIngestHistory.first?.action, .autoMerged)
    }

    func testPureEnglishClipboardAutoFillsChineseTranslation() async {
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "hello" },
            translationService: MockTranslationService(result: .success("你好")),
            dictionaryLookupService: MockDictionaryLookupService(),
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "hello")
        XCTAssertEqual(store.entries.first?.chinese, "你好")
    }

    func testBilingualClipboardDoesNotCallTranslationService() async {
        let service = MockTranslationService(result: .success("不应该调用"))
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "hello\t你好" },
            translationService: service,
            dictionaryLookupService: MockDictionaryLookupService(),
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "hello")
        XCTAssertEqual(store.entries.first?.chinese, "你好")
        XCTAssertEqual(service.callCount, 0)
    }

    func testTranslationFailureStillSavesEnglishWithError() async {
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "hello" },
            translationService: MockTranslationService(result: .failure(TranslationServiceError.emptyTranslation)),
            dictionaryLookupService: MockDictionaryLookupService(),
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "hello")
        XCTAssertEqual(store.entries.first?.chinese, "")
        XCTAssertTrue(store.errorMessage?.contains("翻译失败") == true)
    }

    func testPureChineseClipboardAutoFillsEnglishTranslation() async {
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "你好" },
            translationService: MockTranslationService(result: .success("hello")),
            dictionaryLookupService: MockDictionaryLookupService(),
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "hello")
        XCTAssertEqual(store.entries.first?.chinese, "你好")
    }

    func testPureChineseTranslationFailureStillSavesChineseContent() async {
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { "你好" },
            translationService: MockTranslationService(result: .failure(TranslationServiceError.emptyTranslation)),
            dictionaryLookupService: MockDictionaryLookupService(),
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.first?.english, "你好")
        XCTAssertEqual(store.entries.first?.chinese, "你好")
        XCTAssertTrue(store.errorMessage?.contains("英文补齐失败") == true)
    }

    func testDeleteRemovesEntries() {
        let store = testStore()
        store.addManualEntry(english: "alpha", chinese: "", exampleSentence: "", tags: [], source: "")
        store.addManualEntry(english: "beta", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let firstID = store.entries.first?.id else {
            return XCTFail("Expected entries to exist")
        }

        store.delete(ids: [firstID])
        XCTAssertEqual(store.entries.count, 1)
    }

    func testDueReviewBatchReturnsOnlyUnmasteredDueEntries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let due = VocabularyEntry(
            english: "due",
            isMastered: false,
            nextReviewAt: now.addingTimeInterval(-60)
        )
        let future = VocabularyEntry(
            english: "future",
            isMastered: false,
            nextReviewAt: now.addingTimeInterval(3600)
        )
        let mastered = VocabularyEntry(
            english: "mastered",
            isMastered: true,
            nextReviewAt: now.addingTimeInterval(-60)
        )

        let data = try! JSONEncoder.wordbookEncoder.encode([due, future, mastered])
        let store = testStore()
        try! store.importEntries(from: data)

        let batch = store.dueReviewBatch(count: 5, now: now)
        XCTAssertEqual(batch.map(\.english), ["due"])
    }

    func testDueReviewBatchPrioritizesDueBeforeDifficultEntries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dueOne = VocabularyEntry(
            english: "due one",
            createdAt: now.addingTimeInterval(-10),
            nextReviewAt: now.addingTimeInterval(-60)
        )
        let dueTwo = VocabularyEntry(
            english: "due two",
            createdAt: now.addingTimeInterval(-20),
            nextReviewAt: now.addingTimeInterval(-30)
        )
        let difficult = VocabularyEntry(
            english: "difficult",
            createdAt: now,
            lastReviewedAt: now.addingTimeInterval(-120),
            reviewCount: 0,
            nextReviewAt: now.addingTimeInterval(4 * 3600)
        )

        let data = try! JSONEncoder.wordbookEncoder.encode([difficult, dueOne, dueTwo])
        let store = testStore()
        try! store.importEntries(from: data)

        XCTAssertEqual(store.dueReviewBatch(count: 2, now: now).map(\.english), ["due one", "due two"])
        XCTAssertEqual(store.dueReviewBatch(count: 3, now: now).map(\.english), ["due one", "due two", "difficult"])
    }

    func testDifficultEntriesIncludeForgotAndHardButExcludeMastered() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let forgot = VocabularyEntry(
            english: "forgot",
            lastReviewedAt: now.addingTimeInterval(-60),
            reviewCount: 0,
            nextReviewAt: now.addingTimeInterval(4 * 3600)
        )
        let hard = VocabularyEntry(
            english: "hard",
            lastReviewedAt: now.addingTimeInterval(-60),
            reviewCount: 2,
            nextReviewAt: now.addingTimeInterval(23 * 3600)
        )
        let mastered = VocabularyEntry(
            english: "mastered",
            isMastered: true,
            lastReviewedAt: now.addingTimeInterval(-60),
            reviewCount: 0,
            nextReviewAt: now.addingTimeInterval(4 * 3600)
        )
        let firstRemembered = VocabularyEntry(
            english: "remembered",
            lastReviewedAt: now.addingTimeInterval(-60),
            reviewCount: 1,
            nextReviewAt: Calendar.current.date(byAdding: .day, value: 1, to: now)
        )

        let data = try! JSONEncoder.wordbookEncoder.encode([forgot, hard, mastered, firstRemembered])
        let store = testStore()
        try! store.importEntries(from: data)

        XCTAssertEqual(Set(store.difficultEntries(now: now).map(\.english)), ["forgot", "hard"])
    }

    func testReviewSessionSummaryCountsOutcomesAndUpcomingDue() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let due = VocabularyEntry(english: "due", nextReviewAt: now.addingTimeInterval(3600))
        let data = try! JSONEncoder.wordbookEncoder.encode([due])
        let store = testStore()
        try! store.importEntries(from: data)

        let summary = store.reviewSessionSummary(
            outcomes: [.forgot: 1, .hard: 2, .remembered: 3, .easy: 4],
            now: now
        )

        XCTAssertEqual(summary.completedCount, 10)
        XCTAssertEqual(summary.forgotCount, 1)
        XCTAssertEqual(summary.hardCount, 2)
        XCTAssertEqual(summary.rememberedCount, 3)
        XCTAssertEqual(summary.easyCount, 4)
        XCTAssertEqual(summary.upcomingDueCount, 1)
    }

    func testReviewRememberedSchedulesNextReview() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = testStore()
        store.addManualEntry(english: "interval", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        store.review(entry, outcome: .remembered, now: now)

        XCTAssertEqual(store.entries.first?.reviewCount, 1)
        XCTAssertEqual(store.entries.first?.lastReviewedAt, now)
        XCTAssertEqual(store.entries.first?.nextReviewAt, Calendar.current.date(byAdding: .day, value: 1, to: now))
    }

    func testReviewForgotResetsAndSchedulesFourHoursLater() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = testStore()
        store.addManualEntry(english: "fragile", chinese: "", exampleSentence: "", tags: [], source: "")

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }
        entry.reviewCount = 3
        entry.isMastered = true
        store.update(entry)

        store.review(entry, outcome: .forgot, now: now)

        XCTAssertEqual(store.entries.first?.reviewCount, 0)
        XCTAssertEqual(store.entries.first?.isMastered, false)
        XCTAssertEqual(store.entries.first?.nextReviewAt, Calendar.current.date(byAdding: .hour, value: 4, to: now))
    }

    func testReviewHardKeepsCountAndSchedulesTomorrow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = testStore()
        store.addManualEntry(english: "subtle", chinese: "", exampleSentence: "", tags: [], source: "")

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }
        entry.reviewCount = 2
        store.update(entry)

        store.review(entry, outcome: .hard, now: now)

        XCTAssertEqual(store.entries.first?.reviewCount, 2)
        XCTAssertEqual(store.entries.first?.nextReviewAt, Calendar.current.date(byAdding: .day, value: 1, to: now))
    }

    func testReviewEasyAdvancesTwoIntervals() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = testStore()
        store.addManualEntry(english: "fluent", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        store.review(entry, outcome: .easy, now: now)

        XCTAssertEqual(store.entries.first?.reviewCount, 2)
        XCTAssertEqual(store.entries.first?.nextReviewAt, Calendar.current.date(byAdding: .day, value: 3, to: now))
    }

    func testImportingLegacyJSONKeepsBackwardCompatibility() {
        let legacyJSON = """
        [
          {
            "id": "\(UUID().uuidString)",
            "english": "legacy",
            "chinese": "旧数据",
            "exampleSentence": "",
            "tags": [],
            "source": "old",
            "isFavorite": false,
            "isMastered": false,
            "createdAt": "2024-01-01T00:00:00Z",
            "clipboardRepeatCount": 1
          }
        ]
        """.data(using: .utf8)!

        let store = testStore()
        try! store.importEntries(from: legacyJSON)

        XCTAssertEqual(store.entries.first?.reviewCount, 0)
        XCTAssertNil(store.entries.first?.nextReviewAt)
    }

    func testStatsCountsTodayEntriesReviewsAndAutoCapture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let todayEntry = VocabularyEntry(
            english: "today",
            isFavorite: true,
            createdAt: now,
            lastReviewedAt: now,
            reviewCount: 1,
            nextReviewAt: now.addingTimeInterval(-60)
        )
        let masteredEntry = VocabularyEntry(
            english: "mastered",
            isMastered: true,
            createdAt: now.addingTimeInterval(-86_400)
        )
        let data = try! JSONEncoder.wordbookEncoder.encode([todayEntry, masteredEntry])
        let store = testStore()
        try! store.importEntries(from: data)

        let history = [
            IngestHistoryItem(english: "today", action: .autoCaptured, timestamp: now),
            IngestHistoryItem(english: "older", action: .autoCaptured, timestamp: now.addingTimeInterval(-86_400))
        ]
        let historyData = try! JSONEncoder.wordbookEncoder.encode(history)
        try! historyData.write(to: tempDirectory.appendingPathComponent("ingest-history.json"))
        store.loadHistory()

        let stats = store.stats(now: now)
        XCTAssertEqual(stats.totalEntries, 2)
        XCTAssertEqual(stats.masteredEntries, 1)
        XCTAssertEqual(stats.favoriteEntries, 1)
        XCTAssertEqual(stats.newTodayCount, 1)
        XCTAssertEqual(stats.reviewedTodayCount, 1)
        XCTAssertEqual(stats.autoCapturedTodayCount, 1)
        XCTAssertEqual(stats.dueTodayCount, 1)
        XCTAssertEqual(stats.studyStreakDays, 1)
    }

    func testSearchIndexMatchesAllUserVisibleFields() {
        let store = testStore()
        store.addManualEntry(
            english: "compound interest",
            chinese: "复利",
            exampleSentence: "Interest compounds over time.",
            tags: ["finance"],
            source: "Bob"
        )

        XCTAssertEqual(store.filteredEntries(filter: .all, query: "compound").map(\.english), ["compound interest"])
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "复利").map(\.english), ["compound interest"])
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "over time").map(\.english), ["compound interest"])
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "finance").map(\.english), ["compound interest"])
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "bob").map(\.english), ["compound interest"])
    }

    func testSearchIndexUpdatesAfterEditAndDelete() {
        let store = testStore()
        store.addManualEntry(english: "old phrase", chinese: "", exampleSentence: "", tags: [], source: "")

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        entry.english = "new phrase"
        store.update(entry)

        XCTAssertTrue(store.filteredEntries(filter: .all, query: "old").isEmpty)
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "new").map(\.english), ["new phrase"])

        store.delete(ids: [entry.id])
        XCTAssertTrue(store.filteredEntries(filter: .all, query: "new").isEmpty)
    }

    func testFuzzySearchHandlesLargeImportedDataset() {
        let store = testStore()
        var entries = (0..<3_000).map { index in
            VocabularyEntry(
                english: "generated word \(index)",
                chinese: "生成词 \(index)",
                exampleSentence: "Generated sentence \(index)",
                tags: ["bulk"],
                source: "test"
            )
        }
        entries.append(
            VocabularyEntry(
                english: "anchorword",
                chinese: "锚点词",
                exampleSentence: "The anchorword keeps this search deterministic.",
                tags: ["bulk", "target"],
                source: "test"
            )
        )
        let data = try! JSONEncoder.wordbookEncoder.encode(entries)
        try! store.importEntries(from: data)

        XCTAssertEqual(store.filteredEntries(filter: .all, query: "anchrword").map(\.english), ["anchorword"])
    }

    func testEntryLookupIndexUpdatesAfterEditImportAndDelete() {
        let store = testStore()
        store.addManualEntry(english: "indexed", chinese: "有索引", exampleSentence: "", tags: [], source: "")

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        XCTAssertEqual(store.entry(id: entry.id)?.english, "indexed")

        entry.english = "renamed"
        store.update(entry)
        XCTAssertEqual(store.entry(id: entry.id)?.english, "renamed")

        let imported = VocabularyEntry(english: "imported", chinese: "导入")
        let data = try! JSONEncoder.wordbookEncoder.encode([imported])
        try! store.importEntries(from: data)
        XCTAssertNil(store.entry(id: entry.id))
        XCTAssertEqual(store.entry(id: imported.id)?.english, "imported")

        store.delete(ids: [imported.id])
        XCTAssertNil(store.entry(id: imported.id))
    }

    func testDuplicateMergeUsesUpdatedEnglishIndex() async {
        var clipboardText = "alpha\t一"
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader { clipboardText },
            saveDelay: 0
        )

        await store.addFromClipboardAndWait()

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        entry.english = "beta"
        store.update(entry)

        clipboardText = "beta\t二"
        await store.addFromClipboardAndWait()

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "alpha").count, 0)
        XCTAssertEqual(store.filteredEntries(filter: .all, query: "beta").map(\.id), [entry.id])
    }

    func testTodayDueEntriesIncludesLaterTodayButDueBatchDoesNot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let laterToday = Calendar.current.date(byAdding: .hour, value: 2, to: now)!
        let entry = VocabularyEntry(english: "later", isMastered: false, nextReviewAt: laterToday)
        let data = try! JSONEncoder.wordbookEncoder.encode([entry])
        let store = testStore()
        try! store.importEntries(from: data)

        XCTAssertTrue(store.dueEntries(now: now).isEmpty)
        XCTAssertEqual(store.todayDueEntries(now: now).map(\.english), ["later"])
    }

    func testSaveImmediatelyFlushesDelayedSave() {
        let store = WordbookStore(storageDirectory: tempDirectory, clipboardEnabledOverride: false, saveDelay: 30)
        store.addManualEntry(english: "flush", chinese: "", exampleSentence: "", tags: [], source: "")
        store.saveImmediately()

        let reloaded = testStore()
        XCTAssertEqual(reloaded.entries.first?.english, "flush")
    }

    func testEditingExistingEntryPersistsContentChanges() {
        let store = testStore()
        store.addManualEntry(english: "persist", chinese: "旧释义", exampleSentence: "", tags: [], source: "")

        guard var entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        entry.chinese = "新释义"
        entry.isMastered = true
        entry.reviewCount = 5
        store.update(entry)
        store.saveImmediately()

        let reloaded = testStore()
        XCTAssertEqual(reloaded.entries.first?.chinese, "新释义")
        XCTAssertEqual(reloaded.entries.first?.isMastered, true)
        XCTAssertEqual(reloaded.entries.first?.reviewCount, 5)
    }

    func testBatchSetMasteredUpdatesOnceAndCanUndo() {
        let store = testStore()
        store.addManualEntry(english: "alpha", chinese: "", exampleSentence: "", tags: [], source: "")
        store.addManualEntry(english: "beta", chinese: "", exampleSentence: "", tags: [], source: "")

        let ids = Set(store.entries.map(\.id))
        store.setMastered(true, ids: ids)

        XCTAssertTrue(store.entries.allSatisfy(\.isMastered))

        store.undo()

        XCTAssertTrue(store.entries.allSatisfy { !$0.isMastered })
    }

    func testBatchDeleteCanUndoDeletedEntries() {
        let store = testStore()
        store.addManualEntry(english: "alpha", chinese: "", exampleSentence: "", tags: [], source: "")
        store.addManualEntry(english: "beta", chinese: "", exampleSentence: "", tags: [], source: "")

        let ids = Set(store.entries.map(\.id))
        store.delete(ids: ids)
        XCTAssertTrue(store.entries.isEmpty)

        store.undo()
        XCTAssertEqual(Set(store.entries.map(\.english)), ["alpha", "beta"])
    }

    func testRelatedEntriesIndexUpdatesAfterExampleEdit() {
        let store = testStore()
        store.addManualEntry(english: "alpha", chinese: "", exampleSentence: "Shared sentence.", tags: [], source: "")
        store.addManualEntry(english: "beta", chinese: "", exampleSentence: "Shared sentence.", tags: [], source: "")

        guard let alpha = store.entries.first(where: { $0.english == "alpha" }),
              var beta = store.entries.first(where: { $0.english == "beta" }) else {
            return XCTFail("Expected entries to exist")
        }

        XCTAssertEqual(store.relatedEntries(for: alpha).map(\.english), ["beta"])

        beta.exampleSentence = "Different sentence."
        store.update(beta)

        XCTAssertTrue(store.relatedEntries(for: alpha).isEmpty)
    }

    func testAutoClipboardCaptureUsesInjectedChangeCount() async {
        var clipboardText = "ignored"
        var changeCount = 10
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            pasteboardReader: ClosurePasteboardReader(changeCount: { changeCount }) { clipboardText },
            saveDelay: 0
        )

        store.setClipboardAutoCaptureEnabled(true)
        clipboardText = "captured\t已捕获"
        changeCount += 1

        try? await Task.sleep(nanoseconds: 1_300_000_000)

        XCTAssertEqual(store.entries.first?.english, "captured")
        store.setClipboardAutoCaptureEnabled(false)
    }

    func testEnsureDictionaryEntryCachesStructuredDefinitions() async {
        let translationService = MockTranslationService(result: .success("问候"))
        let dictionaryService = MockDictionaryLookupService()
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            translationService: translationService,
            dictionaryLookupService: dictionaryService,
            saveDelay: 0
        )
        store.addManualEntry(english: "hello", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        await store.ensureDictionaryEntry(for: entry)

        let cached = store.dictionaryEntry(for: "hello")
        XCTAssertEqual(cached?.word, "hello")
        XCTAssertEqual(cached?.meanings.first?.partOfSpeech, "noun")
        XCTAssertEqual(cached?.meanings.first?.definitions.first?.chineseDefinition, "问候")
        XCTAssertEqual(dictionaryService.callCount, 1)
    }

    func testEnsureDictionaryEntryUsesCacheByDefault() async {
        let dictionaryService = MockDictionaryLookupService()
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            translationService: MockTranslationService(result: .success("问候")),
            dictionaryLookupService: dictionaryService,
            saveDelay: 0
        )
        store.addManualEntry(english: "hello", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        await store.ensureDictionaryEntry(for: entry)
        await store.ensureDictionaryEntry(for: entry)

        XCTAssertEqual(dictionaryService.callCount, 1)
    }

    func testRefreshDictionaryBypassesCache() async {
        let dictionaryService = MockDictionaryLookupService()
        let store = WordbookStore(
            storageDirectory: tempDirectory,
            clipboardEnabledOverride: false,
            translationService: MockTranslationService(result: .success("问候")),
            dictionaryLookupService: dictionaryService,
            saveDelay: 0
        )
        store.addManualEntry(english: "hello", chinese: "", exampleSentence: "", tags: [], source: "")

        guard let entry = store.entries.first else {
            return XCTFail("Expected entry to exist")
        }

        await store.ensureDictionaryEntry(for: entry)
        await store.ensureDictionaryEntry(for: entry, forceRefresh: true)

        XCTAssertEqual(dictionaryService.callCount, 2)
    }

    private func testStore() -> WordbookStore {
        WordbookStore(storageDirectory: tempDirectory, clipboardEnabledOverride: false, saveDelay: 0)
    }
}

@MainActor
private final class MockTranslationService: TranslationServicing {
    private let result: Result<String, Error>
    private(set) var callCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func translate(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> String {
        callCount += 1
        return try result.get()
    }
}

private final class MockDictionaryLookupService: DictionaryLookupServicing {
    private(set) var callCount = 0

    func lookup(word: String) async throws -> DictionaryLookupEntry {
        callCount += 1
        return DictionaryLookupEntry(
            word: word,
            phonetic: "həˈləʊ",
            meanings: [
                DictionaryLookupMeaning(
                    partOfSpeech: "noun",
                    definitions: [
                        DictionaryLookupDefinition(
                            definition: "a greeting",
                            example: "hello there",
                            synonyms: ["hi"]
                        )
                    ]
                )
            ]
        )
    }
}

private extension JSONEncoder {
    static var wordbookEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
