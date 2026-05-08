import Foundation

/// 负责 JSON 文件读写、备份与防抖保存，不感知业务模型细节。
final class PersistenceController {
    private let fileURL: URL
    private let backupURL: URL
    private let historyURL: URL
    private let dictionaryCacheURL: URL
    private let decoder = JSONDecoder()
    private let saveDelay: TimeInterval
    private let maxHistoryCount = 80
    private var pendingSaveTask: Task<Void, Never>?
    private let saveQueue = DispatchQueue(label: "Wordbook.PersistenceController.save")
    private var lastSavedFingerprint: Int?
    var onError: ((String) -> Void)?

    init(storageDirectory: URL?, saveDelay: TimeInterval = 0.4) {
        decoder.dateDecodingStrategy = .iso8601

        let dir = StorageLocationResolver(explicitDirectory: storageDirectory).wordbookDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("entries.json")
        backupURL = dir.appendingPathComponent("entries.backup.json")
        historyURL = dir.appendingPathComponent("ingest-history.json")
        dictionaryCacheURL = dir.appendingPathComponent("dictionary-cache.json")
        self.saveDelay = saveDelay
    }

    var entriesFileURL: URL { fileURL }
    var entriesBackupURL: URL { backupURL }
    var entriesHistoryURL: URL { historyURL }

    // MARK: - Entries

    func loadEntries() throws -> [VocabularyEntry]? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([VocabularyEntry].self, from: data)
        }
        // 从旧版本（v1.0 之前）的工作目录迁移数据
        if let migrated = try migrateFromLegacyLocation() {
            saveEntriesImmediately(migrated)
            return migrated
        }
        return nil
    }

    private func migrateFromLegacyLocation() throws -> [VocabularyEntry]? {
        let cwdEntryFile = URL(fileURLWithPath: "entries.json", relativeTo: nil)
        guard FileManager.default.fileExists(atPath: cwdEntryFile.path) else { return nil }
        let data = try Data(contentsOf: cwdEntryFile)
        let entries = try decoder.decode([VocabularyEntry].self, from: data)
        // 连同备份一起迁移
        let cwdBackup = URL(fileURLWithPath: "entries.backup.json", relativeTo: nil)
        if FileManager.default.fileExists(atPath: cwdBackup.path) {
            try? FileManager.default.copyItem(at: cwdBackup, to: backupURL)
        }
        return entries
    }

    func saveEntries(_ entries: [VocabularyEntry], immediately: Bool = false) {
        if immediately {
            flush(entries: entries, wait: true)
        } else {
            scheduleSave(entries: entries)
        }
    }

    func saveEntriesImmediately(_ entries: [VocabularyEntry]) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        flush(entries: entries, wait: true)
    }

    func tryRecoverFromBackup() throws -> [VocabularyEntry]? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        let backupData = try Data(contentsOf: backupURL)
        return try decoder.decode([VocabularyEntry].self, from: backupData)
    }

    func exportEntriesData(_ entries: [VocabularyEntry]) throws -> Data {
        try Self.configuredEncoder().encode(entries)
    }

    // MARK: - History

    func loadHistory() throws -> [IngestHistoryItem] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        let data = try Data(contentsOf: historyURL)
        return try decoder.decode([IngestHistoryItem].self, from: data)
    }

    func saveHistory(_ history: [IngestHistoryItem]) {
        let capped = Array(history.prefix(maxHistoryCount))
        do {
            let data = try Self.configuredEncoder().encode(capped)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            onError?("保存收录历史失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Dictionary Cache

    func loadDictionaryCache() throws -> [String: DictionaryEntryCache] {
        guard FileManager.default.fileExists(atPath: dictionaryCacheURL.path) else { return [:] }
        let data = try Data(contentsOf: dictionaryCacheURL)
        return try decoder.decode([String: DictionaryEntryCache].self, from: data)
    }

    func saveDictionaryCache(_ cache: [String: DictionaryEntryCache]) {
        do {
            let data = try Self.configuredEncoder().encode(cache)
            try data.write(to: dictionaryCacheURL, options: .atomic)
        } catch {
            onError?("保存词典缓存失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Snapshots

    private var snapshotsDir: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("snapshots", isDirectory: true)
    }

    struct SnapshotInfo: Identifiable {
        let id: String
        let date: Date
        let entryCount: Int
        let displayName: String
    }

    func availableSnapshots() -> [SnapshotInfo] {
        guard FileManager.default.fileExists(atPath: snapshotsDir.path) else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> SnapshotInfo? in
                let url = snapshotsDir.appendingPathComponent(name)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let date = attrs[.modificationDate] as? Date else { return nil }
                let count: Int
                if let data = try? Data(contentsOf: url),
                   let entries = try? decoder.decode([VocabularyEntry].self, from: data) {
                    count = entries.count
                } else {
                    count = 0
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "MM-dd HH:mm"
                return SnapshotInfo(id: name, date: date, entryCount: count, displayName: formatter.string(from: date))
            }
            .sorted { $0.date > $1.date }
            .prefix(30)
            .map { $0 }
    }

    func saveSnapshot(_ entries: [VocabularyEntry]) {
        let dir = snapshotsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: Date())).json"
        let url = dir.appendingPathComponent(filename)
        do {
            let data = try Self.configuredEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            onError?("快照保存失败：\(error.localizedDescription)")
        }
    }

    func autoSnapshotIfNeeded(_ entries: [VocabularyEntry]) {
        let dir = snapshotsDir
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "\(formatter.string(from: Date())).json"
        let url = dir.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        saveSnapshot(entries)
        pruneSnapshots()
    }

    func loadSnapshot(id: String) throws -> [VocabularyEntry] {
        let url = snapshotsDir.appendingPathComponent(id)
        let data = try Data(contentsOf: url)
        return try decoder.decode([VocabularyEntry].self, from: data)
    }

    func deleteSnapshot(id: String) {
        let url = snapshotsDir.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: url)
    }

    private func pruneSnapshots() {
        let snapshots = availableSnapshots()
        guard snapshots.count > 30 else { return }
        for snapshot in snapshots.suffix(from: 30) {
            deleteSnapshot(id: snapshot.id)
        }
    }

    // MARK: - Private

    private func flush(entries: [VocabularyEntry], wait: Bool = false) {
        let work = { [self] in
            do {
                let data = try Self.configuredEncoder().encode(entries)
                var hasher = Hasher()
                data.hash(into: &hasher)
                let currentFingerprint = hasher.finalize()
                guard currentFingerprint != lastSavedFingerprint else { return }

                try backupIfNeeded()
                try data.write(to: fileURL, options: .atomic)
                lastSavedFingerprint = currentFingerprint
            } catch {
                onError?("保存失败：\(error.localizedDescription)")
            }
        }

        if wait {
            saveQueue.sync(execute: work)
        } else {
            saveQueue.async(execute: work)
        }
    }

    private func scheduleSave(entries: [VocabularyEntry]) {
        pendingSaveTask?.cancel()
        guard saveDelay > 0 else {
            flush(entries: entries, wait: true)
            return
        }
        let delay = UInt64(saveDelay * 1_000_000_000)
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.flush(entries: entries)
        }
    }

    private func backupIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let tempBackup = backupURL.appendingPathExtension("tmp")
        try? FileManager.default.removeItem(at: tempBackup)
        try FileManager.default.copyItem(at: fileURL, to: tempBackup)
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: tempBackup, to: backupURL)
    }

    private static func configuredEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
