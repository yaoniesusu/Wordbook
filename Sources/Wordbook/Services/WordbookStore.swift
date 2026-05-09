import Combine
import Foundation
import SwiftUI

private struct CachedStats {
    let day: Date
    let value: WordbookStats
}

private struct CachedDueEntries {
    let minuteBucket: Int
    let value: [VocabularyEntry]
}

private struct CachedTodayDueEntries {
    let day: Date
    let value: [VocabularyEntry]
}

private struct CachedAllTags {
    let value: [String]
}

private struct CachedRecentReviewedEntries {
    let value: [VocabularyEntry]
}

private enum UndoAction: Codable {
    case delete(entries: [VocabularyEntry])
    case update(old: VocabularyEntry, new: VocabularyEntry)
    case batchUpdate(changes: [(old: VocabularyEntry, new: VocabularyEntry)])
    case add(entry: VocabularyEntry)

    private enum CodingKeys: String, CodingKey {
        case type, entries, old, new, changes
    }
    private enum TypeTag: String, Codable {
        case delete, update, batchUpdate, add
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(TypeTag.self, forKey: .type) {
        case .delete:
            self = .delete(entries: try c.decode([VocabularyEntry].self, forKey: .entries))
        case .update:
            self = .update(old: try c.decode(VocabularyEntry.self, forKey: .old),
                           new: try c.decode(VocabularyEntry.self, forKey: .new))
        case .batchUpdate:
            self = .batchUpdate(changes: try c.decode([ChangeRecord].self, forKey: .changes).map { ($0.old, $0.new) })
        case .add:
            self = .add(entry: try c.decode(VocabularyEntry.self, forKey: .entries))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .delete(let entries):
            try c.encode(TypeTag.delete, forKey: .type)
            try c.encode(entries, forKey: .entries)
        case .update(let old, let new):
            try c.encode(TypeTag.update, forKey: .type)
            try c.encode(old, forKey: .old)
            try c.encode(new, forKey: .new)
        case .batchUpdate(let changes):
            try c.encode(TypeTag.batchUpdate, forKey: .type)
            try c.encode(changes.map { ChangeRecord(old: $0.old, new: $0.new) }, forKey: .changes)
        case .add(let entry):
            try c.encode(TypeTag.add, forKey: .type)
            try c.encode(entry, forKey: .entries)
        }
    }

    private struct ChangeRecord: Codable {
        let old: VocabularyEntry
        let new: VocabularyEntry
    }
}

/// 本地 JSON 持久化与词条 CRUD。拆分出 PersistenceController / ReviewEngine 后的协调层。
@MainActor
final class WordbookStore: ObservableObject {
    @Published private(set) var entries: [VocabularyEntry] = []
    @Published private(set) var ingestHistory: [IngestHistoryItem] = []
    @Published private(set) var dictionaryEntries: [String: DictionaryEntryCache] = [:]
    @Published private(set) var dictionaryLoadingWords: Set<String> = []
    @Published private(set) var dictionaryErrors: [String: String] = [:]
    @Published var noticeMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var translationMetadata: [UUID: TranslationResult] = [:]
    @Published var highlightedEntryIDs: Set<UUID> = []

    private let persistence: PersistenceController
    private let pasteboardReader: PasteboardReading
    private let translationService: TranslationServicing
    private let dictionaryLookupService: DictionaryLookupServicing
    private let autoTranslationEnabled: () -> Bool
    private let dictionaryEnhancementEnabled: () -> Bool
    private let preferCachedDefinitions: () -> Bool
    private let saveDelay: TimeInterval
    private var clipboardWatch: AnyCancellable?
    private var lastPasteboardChangeCount: Int = -1
    private var entriesByID: [UUID: VocabularyEntry] = [:]
    private var entryOffsetsByID: [UUID: Int] = [:]
    private var entryIDsByNormalizedEnglish: [String: UUID] = [:]
    private var searchIndex: [UUID: String] = [:]
    private var searchTokens: [UUID: [String]] = [:]
    private var entriesByExampleSentence: [String: [VocabularyEntry]] = [:]
    private var entryVersions: [UUID: Int] = [:]
    private var cachedAllTags: CachedAllTags?
    private var cachedStats: CachedStats?
    private var cachedDueEntries: CachedDueEntries?
    private var cachedTodayDueEntries: CachedTodayDueEntries?
    private var cachedRecentReviewedEntries: CachedRecentReviewedEntries?
    private var undoStack: [UndoAction] = []
    private let maxUndoDepth = 20

    init(
        storageDirectory: URL? = nil,
        clipboardEnabledOverride: Bool? = nil,
        pasteboardReader: PasteboardReading = SystemPasteboardReader(),
        translationService: TranslationServicing = CompositeTranslationService.default,
        dictionaryLookupService: DictionaryLookupServicing = FreeDictionaryLookupService(),
        autoTranslationEnabled: @escaping () -> Bool = {
            UserDefaults.standard.object(forKey: .autoTranslationEnabled) as? Bool ?? true
        },
        dictionaryEnhancementEnabled: @escaping () -> Bool = {
            UserDefaults.standard.object(forKey: .dictionaryEnhancementEnabled) as? Bool ?? true
        },
        preferCachedDefinitions: @escaping () -> Bool = {
            UserDefaults.standard.object(forKey: .preferCachedDefinitions) as? Bool ?? true
        },
        saveDelay: TimeInterval = 0.4
    ) {
        self.persistence = PersistenceController(storageDirectory: storageDirectory, saveDelay: saveDelay)
        self.pasteboardReader = pasteboardReader
        self.translationService = translationService
        self.dictionaryLookupService = dictionaryLookupService
        self.autoTranslationEnabled = autoTranslationEnabled
        self.dictionaryEnhancementEnabled = dictionaryEnhancementEnabled
        self.preferCachedDefinitions = preferCachedDefinitions
        self.saveDelay = saveDelay
        self.persistence.onError = { [weak self] message in
            Task { @MainActor in self?.errorMessage = message }
        }

        load()
        loadHistory()
        loadDictionaryCache()
        loadUndoStack()
        persistence.autoSnapshotIfNeeded(entries)

        let autoOn = clipboardEnabledOverride ?? (UserDefaults.standard.object(forKey: .clipboardAutoCaptureEnabled) as? Bool ?? true)
        setClipboardAutoCaptureEnabled(autoOn)
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        saveUndoStack()
        switch action {
        case .delete(let deletedEntries):
            entries.append(contentsOf: deletedEntries)
            sortEntries()
            for entry in deletedEntries {
                entryVersions[entry.id] = 1
            }
            rebuildIndexesAndInvalidateCaches()
            setNotice("已撤销删除")
        case .update(let old, _):
            updateSilently(old)
            setNotice("已撤销修改")
        case .batchUpdate(let changes):
            applyBatchUpdate(changes.map(\.old), notice: "已撤销批量修改", undoAction: nil)
        case .add(let entry):
            entries.removeAll { $0.id == entry.id }
            entryVersions[entry.id] = nil
            rebuildIndexesAndInvalidateCaches()
            setNotice("已撤销新增")
        }
        save()
    }

    /// 开启/关闭后台剪切板轮询；开启时会忽略当前剪切板，从下一次复制开始记录。
    func setClipboardAutoCaptureEnabled(_ enabled: Bool) {
        clipboardWatch?.cancel()
        clipboardWatch = nil
        guard enabled else { return }
        lastPasteboardChangeCount = pasteboardReader.changeCount
        clipboardWatch = Timer.publish(every: 1.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollPasteboardForAutoCapture()
            }
    }

    private func pollPasteboardForAutoCapture() {
        let cc = pasteboardReader.changeCount
        guard cc != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = cc
        guard let raw = pasteboardReader.plainText() else { return }
        guard ClipboardParser.shouldAutoIngest(raw) else { return }
        let source = UserDefaults.standard.string(forKey: .defaultClipboardSource) ?? ""
        let tagsRaw = UserDefaults.standard.string(forKey: .defaultClipboardTags) ?? ""
        let tags = tagsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        addFromClipboard(mergeTags: tags, sourceHint: source, autoCaptured: true)
    }

    func load() {
        do {
            if let loaded = try persistence.loadEntries() {
                entries = loaded.sorted { $0.createdAt > $1.createdAt }
            } else {
                entries = []
            }
            resetEntryVersions()
            rebuildIndexesAndInvalidateCaches()
            clearError()
        } catch {
            entries = []
            resetEntryVersions()
            rebuildIndexesAndInvalidateCaches()
            setError("读取词条失败，已尝试保留空列表：\(error.localizedDescription)")
            recoverFromBackupIfPossible()
        }
    }

    func save() {
        persistence.saveEntries(entries)
    }

    func saveImmediately() {
        persistence.saveEntriesImmediately(entries)
    }

    func loadHistory() {
        do {
            ingestHistory = (try persistence.loadHistory()).sorted { $0.timestamp > $1.timestamp }
            invalidateDerivedData()
        } catch {
            ingestHistory = []
            invalidateDerivedData()
            setError("读取收录历史失败：\(error.localizedDescription)")
        }
    }

    func loadDictionaryCache() {
        do {
            dictionaryEntries = try persistence.loadDictionaryCache()
            dictionaryErrors = [:]
            dictionaryLoadingWords = []
        } catch {
            dictionaryEntries = [:]
            setError("读取词典缓存失败：\(error.localizedDescription)")
        }
    }

    /// 从任意文本添加（拖拽等场景），不依赖剪切板。
    func addFromDroppedText(_ text: String, mergeTags: [String] = [], sourceHint: String = "") {
        let parsed = ClipboardParser.parseBobStyle(text)
        addParsedClipboardEntry(parsed, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: false)
    }

    /// 从剪切板添加：若与已有条目的英文主键相同（忽略大小写与首尾空白），则增加重复计数并可选合并中文。
    func addFromClipboard(mergeTags: [String] = [], sourceHint: String = "", autoCaptured: Bool = false) {
        guard let raw = pasteboardReader.plainText() else {
            setError("剪切板里没有可读取的纯文本。")
            return
        }
        let parsed = ClipboardParser.parseBobStyle(raw)
        addParsedClipboardEntry(parsed, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured)
    }

    func addFromClipboardAndWait(mergeTags: [String] = [], sourceHint: String = "", autoCaptured: Bool = false) async {
        guard let raw = pasteboardReader.plainText() else {
            setError("剪切板里没有可读取的纯文本。")
            return
        }
        let parsed = ClipboardParser.parseBobStyle(raw)
        await addParsedClipboardEntryAndWait(parsed, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured)
    }

    func addManualEntry(
        english: String,
        chinese: String,
        exampleSentence: String,
        tags: [String],
        source: String
    ) {
        let trimmedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChinese = chinese.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedEnglish.isEmpty {
            ingest(
                english: trimmedEnglish,
                chinese: trimmedChinese,
                exampleSentence: exampleSentence,
                mergeTags: tags,
                sourceHint: source,
                autoCaptured: false,
                statusPrefix: "已手动添加"
            )
            return
        }

        addParsedClipboardEntry(
            (english: trimmedEnglish, chinese: trimmedChinese, example: exampleSentence),
            mergeTags: tags,
            sourceHint: source,
            autoCaptured: false
        )
    }

    func dictionaryEntry(for english: String) -> DictionaryEntryCache? {
        dictionaryEntries[dictionaryKey(for: english)]
    }

    func dictionaryError(for english: String) -> String? {
        dictionaryErrors[dictionaryKey(for: english)]
    }

    func isDictionaryLoading(for english: String) -> Bool {
        dictionaryLoadingWords.contains(dictionaryKey(for: english))
    }

    func refreshDictionary(for entry: VocabularyEntry) {
        Task {
            await ensureDictionaryEntry(for: entry, forceRefresh: true)
        }
    }

    func entry(id: UUID) -> VocabularyEntry? {
        entriesByID[id]
    }

    func entryVersion(for id: UUID) -> Int {
        entryVersions[id] ?? -1
    }

    func update(_ entry: VocabularyEntry) {
        guard let idx = indexOfEntry(id: entry.id) else { return }
        let old = entries[idx]
        entries[idx] = entry
        sortEntries()
        bumpEntryVersions(for: Set([entry.id]))
        rebuildIndexesAndInvalidateCaches()
        pushUndo(.update(old: old, new: entry))
        setNotice("已保存修改")
        save()
    }

    func setMastered(_ mastered: Bool, ids: Set<UUID>) {
        let changes = ids.compactMap { id -> (old: VocabularyEntry, new: VocabularyEntry)? in
            guard var entry = entry(id: id), entry.isMastered != mastered else { return nil }
            let old = entry
            entry.isMastered = mastered
            return (old, entry)
        }
        guard !changes.isEmpty else { return }
        applyBatchUpdate(
            changes.map(\.new),
            notice: mastered ? "已标记 \(changes.count) 条为已掌握" : "已标记 \(changes.count) 条为学习中",
            undoAction: .batchUpdate(changes: changes)
        )
    }

    func delete(ids: Set<UUID>) {
        let snapshot = entries.filter { ids.contains($0.id) }
        guard !snapshot.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        for id in ids { entryVersions[id] = nil }
        rebuildIndexesAndInvalidateCaches()
        pushUndo(.delete(entries: snapshot))
        setNotice("已删除 \(ids.count) 条词条")
        save()
    }

    func dueReviewBatch(count: Int = 5, now: Date = Date()) -> [VocabularyEntry] {
        ReviewEngine.dueReviewBatch(from: entries, count: count, now: now)
    }

    func difficultEntries(now: Date = Date(), limit: Int? = nil) -> [VocabularyEntry] {
        ReviewEngine.difficultEntries(from: entries, now: now, limit: limit)
    }

    func recentNewEntries(limit: Int = 5, now: Date = Date()) -> [VocabularyEntry] {
        Array(entries
            .filter { Calendar.current.isDate($0.createdAt, inSameDayAs: now) }
            .prefix(limit))
    }

    func reviewSessionSummary(outcomes: [ReviewOutcome: Int], now: Date = Date()) -> ReviewSessionSummary {
        ReviewEngine.reviewSessionSummary(from: entries, outcomes: outcomes, now: now)
    }

    func review(_ entry: VocabularyEntry, outcome: ReviewOutcome, now: Date = Date()) {
        guard let existing = self.entry(id: entry.id) else { return }
        let updated = ReviewEngine.applyReview(to: existing, outcome: outcome, now: now)
        switch outcome {
        case .forgot: setNotice("已记录「没记住」，稍后会再次出现")
        case .hard:   setNotice("已记录「模糊」，明天再巩固")
        case .remembered: setNotice("已记录「记住了」")
        case .easy:   setNotice("已记录「很熟」，下次间隔更长")
        }
        updateSilently(updated)
    }

    func exportEntriesData() throws -> Data {
        try persistence.exportEntriesData(entries)
    }

    func importEntries(from data: Data) throws {
        guard data.count < 50_000_000 else {
            setError("导入文件过大（超过 50 MB），请检查文件。")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([VocabularyEntry].self, from: data)
        guard imported.count <= 100_000 else {
            setError("词条数量超过上限（100,000），请分批导入。")
            return
        }
        let farFuture = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
        guard !imported.contains(where: { $0.createdAt > farFuture || $0.nextReviewAt ?? .distantPast > farFuture }) else {
            setError("导入数据包含异常日期，已拒绝。")
            return
        }
        undoStack.removeAll()
        saveUndoStack()
        entries = imported.sorted { $0.createdAt > $1.createdAt }
        resetEntryVersions()
        rebuildIndexesAndInvalidateCaches()
        setNotice("已导入 \(imported.count) 条词条")
        save()
    }

    var allTags: [String] {
        if let cachedAllTags {
            return cachedAllTags.value
        }
        let value = Array(Set(entries.flatMap(\.tags))).sorted()
        cachedAllTags = CachedAllTags(value: value)
        return value
    }

    /// 清理旧版本中未被过滤的噪音词条（URL、邮箱、代码、纯数字等）
    func removeNoiseEntries() -> Int {
        let toRemove = entries.filter { ClipboardParser.isNoiseText($0.english) }
        guard !toRemove.isEmpty else { return 0 }
        delete(ids: Set(toRemove.map(\.id)))
        return toRemove.count
    }

    var storageFilePath: String {
        persistence.entriesFileURL.path
    }

    var backupFilePath: String {
        persistence.entriesBackupURL.path
    }

    var historyFilePath: String {
        persistence.entriesHistoryURL.path
    }

    struct DayReviewData: Identifiable {
        public let id = UUID()
        public let date: Date
        public let label: String
        public let count: Int
    }

    func last7DaysReviewData() -> [DayReviewData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return DayReviewData(date: today, label: "", count: 0)
            }
            let count = entries.filter { entry in
                guard let reviewed = entry.lastReviewedAt else { return false }
                return calendar.isDate(reviewed, inSameDayAs: date)
            }.count
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return DayReviewData(date: date, label: formatter.string(from: date), count: count)
        }.reversed()
    }

    func availableSnapshots() -> [PersistenceController.SnapshotInfo] {
        persistence.availableSnapshots()
    }

    func saveSnapshotNow() {
        persistence.saveSnapshot(entries)
        setNotice("已保存当前快照")
    }

    func restoreFromSnapshot(id: String) throws {
        let snapshot = try persistence.loadSnapshot(id: id)
        entries = snapshot.sorted { $0.createdAt > $1.createdAt }
        resetEntryVersions()
        rebuildIndexesAndInvalidateCaches()
        saveImmediately()
        setNotice("已从快照恢复")
    }

    func deleteSnapshot(id: String) {
        persistence.deleteSnapshot(id: id)
    }

    func ankiExportText() -> String {
        entries.map { entry in
            let escape: (String) -> String = { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            return "\(escape(entry.english))\t\(escape(entry.chinese))\t\(escape(entry.exampleSentence))"
        }.joined(separator: "\n")
    }

    func relatedEntries(for entry: VocabularyEntry) -> [VocabularyEntry] {
        let example = entry.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !example.isEmpty else { return [] }
        return entriesByExampleSentence[example, default: []].filter { $0.id != entry.id }
    }

    var automaticIngestHistory: [IngestHistoryItem] {
        ingestHistory.filter { $0.action.isAutomatic }
    }

    func stats(now: Date = Date()) -> WordbookStats {
        let day = Calendar.current.startOfDay(for: now)
        if let cachedStats, cachedStats.day == day {
            return cachedStats.value
        }

        let calendar = Calendar.current
        let totalEntries = entries.count
        var masteredEntries = 0
        var favoriteEntries = 0
        var neverReviewedCount = 0
        var newTodayCount = 0
        var reviewedTodayCount = 0
        for entry in entries {
            if entry.isMastered { masteredEntries += 1 }
            if entry.isFavorite { favoriteEntries += 1 }
            if entry.reviewCount == 0 && entry.lastReviewedAt == nil { neverReviewedCount += 1 }
            if calendar.isDate(entry.createdAt, inSameDayAs: now) { newTodayCount += 1 }
            if let r = entry.lastReviewedAt, calendar.isDate(r, inSameDayAs: now) { reviewedTodayCount += 1 }
        }
        let unmasteredEntries = totalEntries - masteredEntries
        let dueTodayCount = todayDueEntries(now: now).count
        let autoCapturedTodayCount = automaticIngestHistory.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }.count
        let studyStreakDays = studyStreakDays(now: now)

        let value = WordbookStats(
            totalEntries: totalEntries,
            masteredEntries: masteredEntries,
            unmasteredEntries: unmasteredEntries,
            neverReviewedCount: neverReviewedCount,
            favoriteEntries: favoriteEntries,
            dueTodayCount: dueTodayCount,
            newTodayCount: newTodayCount,
            reviewedTodayCount: reviewedTodayCount,
            autoCapturedTodayCount: autoCapturedTodayCount,
            uniqueTagCount: allTags.count,
            studyStreakDays: studyStreakDays
        )
        cachedStats = CachedStats(day: day, value: value)
        return value
    }

    func dueEntries(now: Date = Date()) -> [VocabularyEntry] {
        let bucket = Int(now.timeIntervalSince1970 / 60)
        if let cachedDueEntries, cachedDueEntries.minuteBucket == bucket {
            return cachedDueEntries.value
        }
        let value = ReviewEngine.dueEntries(from: entries, now: now)
        cachedDueEntries = CachedDueEntries(minuteBucket: bucket, value: value)
        return value
    }

    func todayDueEntries(now: Date = Date()) -> [VocabularyEntry] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        if let cachedTodayDueEntries, cachedTodayDueEntries.day == day {
            return cachedTodayDueEntries.value
        }
        let value = ReviewEngine.todayDueEntries(from: entries, now: now)
        cachedTodayDueEntries = CachedTodayDueEntries(day: day, value: value)
        return value
    }

    func recentReviewedEntries(limit: Int = 5) -> [VocabularyEntry] {
        if let cachedRecentReviewedEntries {
            return Array(cachedRecentReviewedEntries.value.prefix(limit))
        }
        let value = entries
            .filter { $0.lastReviewedAt != nil }
            .sorted { ($0.lastReviewedAt ?? .distantPast) > ($1.lastReviewedAt ?? .distantPast) }
        cachedRecentReviewedEntries = CachedRecentReviewedEntries(value: value)
        return Array(value.prefix(limit))
    }

    private func ingest(
        english: String,
        chinese: String,
        exampleSentence: String,
        mergeTags: [String],
        sourceHint: String,
        autoCaptured: Bool,
        statusPrefix: String? = nil,
        skipRebuild: Bool = false
    ) {
        let en = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !en.isEmpty else {
            setError("没有可写入的英文词条。")
            return
        }

        let norm = en.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingID = entryIDsByNormalizedEnglish[norm], let idx = indexOfEntry(id: existingID) {
            if entries[idx].chinese.isEmpty, !chinese.isEmpty {
                entries[idx].chinese = chinese
            }
            if entries[idx].exampleSentence.isEmpty, !exampleSentence.isEmpty {
                entries[idx].exampleSentence = exampleSentence
            }
            if !mergeTags.isEmpty {
                entries[idx].tags = Array(Set(entries[idx].tags + mergeTags)).sorted()
            }
            if !sourceHint.isEmpty, entries[idx].source.isEmpty {
                entries[idx].source = sourceHint
            }
            appendHistory(
                english: entries[idx].english,
                chinese: entries[idx].chinese,
                source: sourceHint.isEmpty ? entries[idx].source : sourceHint,
                tags: entries[idx].tags,
                action: autoCaptured ? .autoMerged : .manualMerged
            )
            if !skipRebuild { rebuildIndexesAndInvalidateCaches() }
            bumpEntryVersions(for: Set([entries[idx].id]))
            setNotice(autoCaptured ? "已自动合并：\(entries[idx].english)" : "已合并到现有词条：\(entries[idx].english)")
            scheduleDictionaryLookupIfNeeded(for: entries[idx], forceRefresh: entries[idx].chinese.isEmpty)
        } else {
            let e = VocabularyEntry(
                english: en,
                chinese: chinese,
                exampleSentence: exampleSentence,
                tags: Array(Set(mergeTags)).sorted(),
                source: sourceHint
            )
            entries.insert(e, at: 0)
            highlightEntry(e.id)
            appendHistory(
                english: e.english,
                chinese: e.chinese,
                source: e.source,
                tags: e.tags,
                action: autoCaptured ? .autoCaptured : .manualCreated
            )
            entryVersions[e.id] = 0
            if !skipRebuild { rebuildIndexesAndInvalidateCaches() }
            setNotice("\(statusPrefix ?? (autoCaptured ? "已自动收录" : "已添加"))：\(e.english)")
            scheduleDictionaryLookupIfNeeded(for: e)
        }
        if !skipRebuild { save() }
    }

    private func addParsedClipboardEntry(
        _ parsed: (english: String, chinese: String, example: String),
        mergeTags: [String],
        sourceHint: String,
        autoCaptured: Bool
    ) {
        Task {
            await addParsedClipboardEntryAndWait(parsed, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured)
        }
    }

    func ensureDictionaryEntry(for entry: VocabularyEntry, forceRefresh: Bool = false) async {
        let english = entry.english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dictionaryEnhancementEnabled(), !english.isEmpty else { return }
        guard english.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return }

        let key = dictionaryKey(for: english)
        if !forceRefresh, preferCachedDefinitions(), dictionaryEntries[key] != nil {
            return
        }
        guard !dictionaryLoadingWords.contains(key) else { return }

        dictionaryLoadingWords.insert(key)
        dictionaryErrors[key] = nil
        defer { dictionaryLoadingWords.remove(key) }

        do {
            let lookedUp = try await dictionaryLookupService.lookup(word: english)
            let cached = try await buildDictionaryCache(from: lookedUp)
            dictionaryEntries[key] = cached
            dictionaryErrors[key] = nil
            saveDictionaryCache()
        } catch {
            dictionaryErrors[key] = error.localizedDescription
        }
    }

    private func addParsedClipboardEntryAndWait(
        _ parsed: (english: String, chinese: String, example: String),
        mergeTags: [String],
        sourceHint: String,
        autoCaptured: Bool
    ) async {
        let english = parsed.english.trimmingCharacters(in: .whitespacesAndNewlines)
        let chinese = parsed.chinese.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !english.isEmpty || !chinese.isEmpty else {
            setError("没有可写入的词条。")
            return
        }

        if !english.isEmpty && !chinese.isEmpty {
            ingest(
                english: english,
                chinese: chinese,
                exampleSentence: parsed.example,
                mergeTags: mergeTags,
                sourceHint: sourceHint,
                autoCaptured: autoCaptured
            )
            return
        }

        if !english.isEmpty {
            // 长句拆分：6词+自动打散为单词
            if english.count <= 500, let splitResult = SentenceSplitter.splitIfNeeded(english) {
                let count = splitResult.words.count
                for word in splitResult.words {
                    if autoTranslationEnabled() {
                        do {
                            let (translated, result) = try await translateAndCapture(word, from: .english, to: .chinese)
                            ingest(english: word, chinese: translated, exampleSentence: splitResult.originalSentence, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured, statusPrefix: nil, skipRebuild: true)
                            if let result, let lastID = entries.first?.id { translationMetadata[lastID] = result }
                        } catch {
                            ingest(english: word, chinese: "", exampleSentence: splitResult.originalSentence, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured, skipRebuild: true)
                        }
                    } else {
                        ingest(english: word, chinese: "", exampleSentence: splitResult.originalSentence, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured, skipRebuild: true)
                    }
                }
                rebuildIndexesAndInvalidateCaches()
                save()
                setNotice(autoCaptured ? "已自动拆分收录 \(count) 个单词" : "已拆分添加 \(count) 个单词")
                return
            }

            guard autoTranslationEnabled(), english.count <= 500 else {
                ingest(english: english, chinese: "", exampleSentence: parsed.example, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured)
                return
            }

            do {
                let (translated, result) = try await translateAndCapture(english, from: .english, to: .chinese)
                ingest(english: english, chinese: translated, exampleSentence: parsed.example, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured, statusPrefix: autoCaptured ? "已自动补齐" : "已补齐翻译")
                if let result, let lastID = entries.first?.id { translationMetadata[lastID] = result }
            } catch {
                ingest(english: english, chinese: "", exampleSentence: parsed.example, mergeTags: mergeTags, sourceHint: sourceHint, autoCaptured: autoCaptured)
                setError("翻译失败，已保存英文待补齐：\(error.localizedDescription)")
            }
            return
        }

        guard autoTranslationEnabled(), chinese.count <= 500 else {
            ingest(
                english: chinese,
                chinese: chinese,
                exampleSentence: parsed.example,
                mergeTags: mergeTags,
                sourceHint: sourceHint,
                autoCaptured: autoCaptured,
                statusPrefix: autoCaptured ? "已自动收录" : "已添加"
            )
            setError("暂时无法补齐英文，先按原中文保存。")
            return
        }

        do {
            let (translated, result) = try await translateAndCapture(chinese, from: .chinese, to: .english)
            ingest(
                english: translated,
                chinese: chinese,
                exampleSentence: parsed.example,
                mergeTags: mergeTags,
                sourceHint: sourceHint,
                autoCaptured: autoCaptured,
                statusPrefix: autoCaptured ? "已自动补齐" : "已补齐翻译"
            )
            if let result, let lastID = entries.first?.id {
                translationMetadata[lastID] = result
            }
        } catch {
            ingest(
                english: chinese,
                chinese: chinese,
                exampleSentence: parsed.example,
                mergeTags: mergeTags,
                sourceHint: sourceHint,
                autoCaptured: autoCaptured,
                statusPrefix: autoCaptured ? "已自动收录" : "已添加"
            )
            setError("英文补齐失败，先按原中文保存：\(error.localizedDescription)")
        }
    }

    private func recoverFromBackupIfPossible() {
        do {
            if let recovered = try persistence.tryRecoverFromBackup() {
                entries = recovered.sorted { $0.createdAt > $1.createdAt }
                resetEntryVersions()
                rebuildIndexesAndInvalidateCaches()
                setNotice("主数据损坏，已从最近一次备份恢复。")
            }
        } catch {
            setError("备份恢复也失败了：\(error.localizedDescription)")
        }
    }

    private func saveDictionaryCache() {
        persistence.saveDictionaryCache(dictionaryEntries)
    }

    private func updateSilently(_ entry: VocabularyEntry) {
        guard let idx = indexOfEntry(id: entry.id) else { return }
        entries[idx] = entry
        sortEntries()
        bumpEntryVersions(for: Set([entry.id]))
        rebuildIndexesAndInvalidateCaches()
        save()
    }

    private func applyBatchUpdate(_ updatedEntries: [VocabularyEntry], notice: String, undoAction: UndoAction?) {
        let updatedByID = Dictionary(uniqueKeysWithValues: updatedEntries.map { ($0.id, $0) })
        entries = entries.map { updatedByID[$0.id] ?? $0 }
        sortEntries()
        bumpEntryVersions(for: Set(updatedEntries.map(\.id)))
        rebuildIndexesAndInvalidateCaches()
        if let undoAction { pushUndo(undoAction) }
        setNotice(notice)
        save()
    }

    private func sortEntries() {
        entries.sort { $0.createdAt > $1.createdAt }
    }

    func filteredEntries(filter: EntryFilter, query: String, sortOrder: SortOrder = .newest) -> [VocabularyEntry] {
        let filteredByStatus: [VocabularyEntry]
        switch filter {
        case .all:
            filteredByStatus = entries
        case .favorites:
            filteredByStatus = entries.filter(\.isFavorite)
        case .unmastered:
            filteredByStatus = entries.filter { !$0.isMastered }
        case .mastered:
            filteredByStatus = entries.filter(\.isMastered)
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return filteredByStatus }
        let queryTokens = q.split(separator: " ").map(String.init)

        let exactResults = filteredByStatus.filter { entry in
            searchIndex[entry.id]?.contains(q) == true
        }
        let result = exactResults.isEmpty
            ? filteredByStatus.filter { entry in
                guard q.count >= 3, let tokens = searchTokens[entry.id] else { return false }
                return FuzzySearchEngine.fuzzyMatch(queryTokens: queryTokens, targetTokens: tokens)
            }
            : exactResults

        switch sortOrder {
        case .newest:
            return result
        case .alphabetical:
            return result.sorted { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
        case .dueFirst:
            return result.sorted { ($0.nextReviewAt ?? .distantFuture) < ($1.nextReviewAt ?? .distantFuture) }
        }
    }

    private func rebuildIndexesAndInvalidateCaches() {
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entryOffsetsByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        entryIDsByNormalizedEnglish = Dictionary(
            entries.map { (normalizedEnglishKey(for: $0.english), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        searchIndex = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, normalizedSearchText(for: $0)) })
        searchTokens = Dictionary(uniqueKeysWithValues: entries.map { entry in
            let indexText = searchIndex[entry.id] ?? normalizedSearchText(for: entry)
            return (entry.id, tokenizedSearchText(indexText))
        })
        entriesByExampleSentence = Dictionary(grouping: entries) {
            $0.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.key.isEmpty }
        for entry in entries where entryVersions[entry.id] == nil {
            entryVersions[entry.id] = 0
        }
        invalidateDerivedData()
    }

    private func invalidateDerivedData() {
        cachedAllTags = nil
        cachedStats = nil
        cachedDueEntries = nil
        cachedTodayDueEntries = nil
        cachedRecentReviewedEntries = nil
    }

    private func normalizedSearchText(for entry: VocabularyEntry) -> String {
        [
            entry.english,
            entry.chinese,
            entry.exampleSentence,
            entry.tags.joined(separator: " "),
            entry.source
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func tokenizedSearchText(_ text: String) -> [String] {
        Array(Set(text
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
            .filter { $0.count <= 48 }))
            .prefix(80)
            .map { $0 }
    }

    private func resetEntryVersions() {
        entryVersions = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, 0) })
    }

    private func bumpEntryVersions(for ids: Set<UUID>) {
        for id in ids {
            entryVersions[id, default: 0] += 1
        }
    }

    private func scheduleDictionaryLookupIfNeeded(for entry: VocabularyEntry, forceRefresh: Bool = false) {
        guard dictionaryEnhancementEnabled() else { return }
        Task {
            await ensureDictionaryEntry(for: entry, forceRefresh: forceRefresh)
        }
    }

    private func dictionaryKey(for english: String) -> String {
        english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func translateAndCapture(_ text: String, from source: TranslationLanguage, to target: TranslationLanguage) async throws -> (String, TranslationResult?) {
        if let composite = translationService as? CompositeTranslationService {
            let result = try await composite.translateWithConfidence(text, from: source, to: target)
            return (result.text, result)
        }
        let translated = try await translationService.translate(text, from: source, to: target)
        return (translated, nil)
    }

    private func normalizedEnglishKey(for english: String) -> String {
        english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func indexOfEntry(id: UUID) -> Int? {
        entryOffsetsByID[id]
    }

    private func buildDictionaryCache(from entry: DictionaryLookupEntry) async throws -> DictionaryEntryCache {
        // 先构建结构（英文释义）
        let meanings: [DictionaryMeaningCache] = entry.meanings.compactMap { meaning in
            let definitions: [DictionarySense] = meaning.definitions.compactMap { def in
                let text = def.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return DictionarySense(
                    englishDefinition: text,
                    chineseDefinition: "",
                    example: def.example,
                    translatedExample: nil,
                    synonyms: def.synonyms
                )
            }
            guard !definitions.isEmpty else { return nil }
            return DictionaryMeaningCache(partOfSpeech: meaning.partOfSpeech, definitions: definitions)
        }

        guard !meanings.isEmpty else { throw DictionaryLookupError.emptyResult }

        // 翻译英文释义为中文（最多 3 条，避免过慢）
        let allDefinitions = meanings.prefix(3).flatMap { $0.definitions.map { $0.englishDefinition } }
        var translations: [String: String] = [:]
        for def in allDefinitions {
            do {
                let translated = try await translationService.translate(def, from: .english, to: .chinese)
                let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { translations[def] = trimmed }
            } catch {
                // 单条失败不阻塞
            }
        }

        let filledMeanings = meanings.map { meaning -> DictionaryMeaningCache in
            let filledDefs = meaning.definitions.map { def in
                DictionarySense(
                    englishDefinition: def.englishDefinition,
                    chineseDefinition: translations[def.englishDefinition] ?? def.chineseDefinition,
                    example: def.example,
                    translatedExample: def.translatedExample,
                    synonyms: def.synonyms
                )
            }
            return DictionaryMeaningCache(partOfSpeech: meaning.partOfSpeech, definitions: filledDefs)
        }

        return DictionaryEntryCache(
            word: entry.word,
            phonetic: entry.phonetic,
            meanings: filledMeanings,
            fetchedAt: Date()
        )
    }

    private func studyStreakDays(now: Date) -> Int {
        ReviewEngine.studyStreakDays(from: entries, now: now)
    }

    private func appendHistory(
        english: String,
        chinese: String,
        source: String,
        tags: [String],
        action: IngestHistoryAction
    ) {
        let item = IngestHistoryItem(
            english: english,
            chinese: chinese,
            source: source,
            tags: tags,
            action: action
        )
        ingestHistory.insert(item, at: 0)
        if ingestHistory.count > 80 {
            ingestHistory = Array(ingestHistory.prefix(80))
        }
        invalidateDerivedData()
        saveHistory()
    }

    private func saveHistory() {
        persistence.saveHistory(ingestHistory)
    }

    private func highlightEntry(_ id: UUID) {
        highlightedEntryIDs.insert(id)
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            highlightedEntryIDs.remove(id)
        }
    }

    private func pushUndo(_ action: UndoAction) {
        undoStack.append(action)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
        }
        saveUndoStack()
    }

    private func loadUndoStack() {
        guard let data = persistence.loadUndoStackData() else { return }
        do {
            undoStack = try JSONDecoder().decode([UndoAction].self, from: data)
        } catch {
            // 旧格式或损坏，静默丢弃
        }
    }

    private func saveUndoStack() {
        guard let data = try? JSONEncoder().encode(undoStack) else { return }
        persistence.saveUndoStackData(data)
    }

    private func setNotice(_ message: String) {
        noticeMessage = message
        errorMessage = nil
    }

    private func setError(_ message: String) {
        errorMessage = message
        noticeMessage = nil
    }

    private func clearError() {
        errorMessage = nil
    }
}
