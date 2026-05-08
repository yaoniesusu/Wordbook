import Foundation

enum IngestHistoryAction: String, Codable, CaseIterable {
    case autoCaptured
    case autoMerged
    case manualCreated
    case manualMerged

    var title: String {
        switch self {
        case .autoCaptured: return "自动收录"
        case .autoMerged: return "自动合并"
        case .manualCreated: return "手动添加"
        case .manualMerged: return "手动合并"
        }
    }

    var isAutomatic: Bool {
        switch self {
        case .autoCaptured, .autoMerged: return true
        case .manualCreated, .manualMerged: return false
        }
    }
}

struct IngestHistoryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var english: String
    var chinese: String
    var source: String
    var tags: [String]
    var action: IngestHistoryAction
    var timestamp: Date

    init(
        id: UUID = UUID(),
        english: String,
        chinese: String = "",
        source: String = "",
        tags: [String] = [],
        action: IngestHistoryAction,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.source = source
        self.tags = tags
        self.action = action
        self.timestamp = timestamp
    }
}
