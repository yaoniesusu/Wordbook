import Foundation

/// 单词本中的一条记录：中英对照、例句、标签与来源、学习状态。
struct VocabularyEntry: Identifiable, Codable, Hashable {
    var id: UUID
    /// 英文单词或短语（主词条）
    var english: String
    /// 中文释义或译文
    var chinese: String
    /// 可选：完整例句或上下文（可与主词条不同）
    var exampleSentence: String
    /// 标签，如「工作」「游戏」
    var tags: [String]
    /// 来源说明，如「Bob」「Safari 某页」
    var source: String
    var isFavorite: Bool
    var isMastered: Bool
    var createdAt: Date
    /// 最近一次复习时间。
    var lastReviewedAt: Date?
    /// 复习成功累计次数，用于计算下次复习时间。
    var reviewCount: Int
    /// 下次建议复习时间；为空表示尚未进入复习节奏。
    var nextReviewAt: Date?
    /// SM-2 易度因子，默认 2.5，范围 [1.3, 2.5]。
    var easinessFactor: Double

    init(
        id: UUID = UUID(),
        english: String,
        chinese: String = "",
        exampleSentence: String = "",
        tags: [String] = [],
        source: String = "",
        isFavorite: Bool = false,
        isMastered: Bool = false,
        createdAt: Date = Date(),
        lastReviewedAt: Date? = nil,
        reviewCount: Int = 0,
        nextReviewAt: Date? = nil,
        easinessFactor: Double = 2.5
    ) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.exampleSentence = exampleSentence
        self.tags = tags
        self.source = source
        self.isFavorite = isFavorite
        self.isMastered = isMastered
        self.createdAt = createdAt
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
        self.nextReviewAt = nextReviewAt
        self.easinessFactor = easinessFactor
    }

    enum CodingKeys: String, CodingKey {
        case id
        case english
        case chinese
        case exampleSentence
        case tags
        case source
        case isFavorite
        case isMastered
        case createdAt
        case lastReviewedAt
        case reviewCount
        case nextReviewAt
        case easinessFactor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        english = try container.decodeIfPresent(String.self, forKey: .english) ?? ""
        chinese = try container.decodeIfPresent(String.self, forKey: .chinese) ?? ""
        exampleSentence = try container.decodeIfPresent(String.self, forKey: .exampleSentence) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isMastered = try container.decodeIfPresent(Bool.self, forKey: .isMastered) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt)
        easinessFactor = try container.decodeIfPresent(Double.self, forKey: .easinessFactor) ?? 2.5
    }
}
