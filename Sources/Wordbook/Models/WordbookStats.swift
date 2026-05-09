import Foundation

struct WordbookStats {
    let totalEntries: Int
    let masteredEntries: Int
    let unmasteredEntries: Int
    let neverReviewedCount: Int
    let favoriteEntries: Int
    let dueTodayCount: Int
    let newTodayCount: Int
    let reviewedTodayCount: Int
    let autoCapturedTodayCount: Int
    let uniqueTagCount: Int
    let studyStreakDays: Int

    var masteryRateText: String {
        guard totalEntries > 0 else { return "0%" }
        let ratio = Double(masteredEntries) / Double(totalEntries)
        return "\(Int((ratio * 100).rounded()))%"
    }
}
