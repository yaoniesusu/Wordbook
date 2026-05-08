import Foundation

enum ReviewOutcome: Hashable {
    case forgot
    case hard
    case remembered
    case easy

    var title: String {
        switch self {
        case .forgot: return "没记住"
        case .hard: return "模糊"
        case .remembered: return "记住了"
        case .easy: return "很熟"
        }
    }
}

struct ReviewSessionSummary {
    let completedCount: Int
    let forgotCount: Int
    let hardCount: Int
    let rememberedCount: Int
    let easyCount: Int
    let upcomingDueCount: Int
}

/// 纯函数式间隔重复逻辑，不持有状态。
enum ReviewEngine {

    /// SM-2: 根据 EF 和 reviewCount 计算下次间隔（天）。
    static func nextInterval(reviewCount: Int, easinessFactor: Double) -> Int {
        if reviewCount <= 0 { return 1 }
        if reviewCount == 1 { return 1 }
        if reviewCount == 2 { return 3 }
        return max(1, Int(Double(reviewCount) * easinessFactor))
    }

    /// SM-2: 计算新的易度因子。
    static func updatedEasinessFactor(current: Double, quality: Int) -> Double {
        let q = Double(quality)
        let delta = 0.1 - (5.0 - q) * (0.08 + (5.0 - q) * 0.02)
        return max(1.3, current + delta)
    }

    /// 应用 SM-2 复习结果，返回更新后的词条。
    static func applyReview(to entry: VocabularyEntry, outcome: ReviewOutcome, now: Date) -> VocabularyEntry {
        var updated = entry
        updated.lastReviewedAt = now

        switch outcome {
        case .forgot:
            updated.reviewCount = 0
            updated.isMastered = false
            updated.easinessFactor = max(1.3, updated.easinessFactor - 0.2)
            updated.nextReviewAt = Calendar.current.date(byAdding: .hour, value: 4, to: now)
        case .hard:
            updated.isMastered = false
            updated.easinessFactor = updatedEasinessFactor(current: updated.easinessFactor, quality: 2)
            updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: now)
        case .remembered:
            updated.reviewCount += 1
            updated.easinessFactor = updatedEasinessFactor(current: updated.easinessFactor, quality: 4)
            let interval = nextInterval(reviewCount: updated.reviewCount, easinessFactor: updated.easinessFactor)
            updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: interval, to: now)
            if updated.reviewCount >= 5 { updated.isMastered = true }
        case .easy:
            updated.reviewCount += 2
            updated.easinessFactor = updatedEasinessFactor(current: updated.easinessFactor, quality: 5)
            let interval = nextInterval(reviewCount: updated.reviewCount, easinessFactor: updated.easinessFactor)
            updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: interval, to: now)
            if updated.reviewCount >= 5 { updated.isMastered = true }
        }

        return updated
    }

    static func isDifficult(_ entry: VocabularyEntry, now: Date) -> Bool {
        guard !entry.isMastered else { return false }
        if entry.reviewCount == 0, entry.lastReviewedAt != nil {
            return true
        }
        guard let nextReviewAt = entry.nextReviewAt else { return false }
        let hardRetryWindow = Calendar.current.date(byAdding: .day, value: 1, to: entry.lastReviewedAt ?? entry.createdAt) ?? now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return entry.reviewCount >= 2 && entry.reviewCount <= 3 && nextReviewAt <= hardRetryWindow && nextReviewAt <= tomorrow
    }

    /// 已到期词条（未掌握且 nextReviewAt <= now）。
    static func dueEntries(from entries: [VocabularyEntry], now: Date) -> [VocabularyEntry] {
        entries.filter {
            guard !$0.isMastered else { return false }
            guard let nextReviewAt = $0.nextReviewAt else { return true }
            return nextReviewAt <= now
        }
    }

    /// 今天内到期词条（未掌握且 nextReviewAt < 明天开始）。
    static func todayDueEntries(from entries: [VocabularyEntry], now: Date) -> [VocabularyEntry] {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return entries.filter {
            guard !$0.isMastered else { return false }
            guard let nextReviewAt = $0.nextReviewAt else { return true }
            return nextReviewAt < startOfTomorrow
        }
    }

    /// 取一批待复习词条：到期词优先，其次难词。
    static func dueReviewBatch(from entries: [VocabularyEntry], count: Int, now: Date) -> [VocabularyEntry] {
        let due = dueEntries(from: entries, now: now)
        let hard = difficultEntries(from: entries, now: now).filter { difficult in
            !due.contains { $0.id == difficult.id }
        }
        return Array((due + hard).prefix(count))
    }

    static func difficultEntries(from entries: [VocabularyEntry], now: Date, limit: Int? = nil) -> [VocabularyEntry] {
        let value = entries
            .filter { isDifficult($0, now: now) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.nextReviewAt ?? lhs.lastReviewedAt ?? lhs.createdAt
                let rhsDate = rhs.nextReviewAt ?? rhs.lastReviewedAt ?? rhs.createdAt
                return lhsDate < rhsDate
            }

        guard let limit else { return value }
        return Array(value.prefix(limit))
    }

    static func reviewSessionSummary(from entries: [VocabularyEntry], outcomes: [ReviewOutcome: Int], now: Date) -> ReviewSessionSummary {
        ReviewSessionSummary(
            completedCount: outcomes.values.reduce(0, +),
            forgotCount: outcomes[.forgot, default: 0],
            hardCount: outcomes[.hard, default: 0],
            rememberedCount: outcomes[.remembered, default: 0],
            easyCount: outcomes[.easy, default: 0],
            upcomingDueCount: todayDueEntries(from: entries, now: now).count
        )
    }

    static func studyStreakDays(from entries: [VocabularyEntry], now: Date) -> Int {
        let calendar = Calendar.current
        let reviewedDays = Set(entries.compactMap { entry -> Date? in
            guard let lastReviewedAt = entry.lastReviewedAt else { return nil }
            return calendar.startOfDay(for: lastReviewedAt)
        })
        var cursor = calendar.startOfDay(for: now)
        var streak = 0
        while reviewedDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }
        return streak
    }
}
