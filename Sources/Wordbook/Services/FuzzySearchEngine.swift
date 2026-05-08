import Foundation

/// 模糊搜索：编辑距离容错，精确搜索无结果时回退。
enum FuzzySearchEngine {

    /// Levenshtein 编辑距离。
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i-1] == b[j-1] ? 0 : 1
                let current = min(dp[j] + 1, dp[j-1] + 1, prev + substitutionCost)
                prev = dp[j]
                dp[j] = current
            }
        }
        return dp[b.count]
    }

    /// 根据查询长度动态调整最大容错距离：短词最多容错1，长词最多容错3。
    static func maxDistance(for query: String) -> Int {
        let len = query.count
        if len <= 3 { return 1 }
        if len <= 6 { return 2 }
        return 3
    }

    /// 判断 query 是否与 target 中的某个词模糊匹配。
    /// 将 query 和 target 分别拆分为空白分隔的词，检查是否存在匹配词对。
    static func fuzzyMatch(query: String, target: String) -> Bool {
        let queryTokens = query.lowercased().split(separator: " ").map(String.init)
        let targetTokens = target.lowercased().split(separator: " ").map(String.init)
        return fuzzyMatch(queryTokens: queryTokens, targetTokens: targetTokens)
    }

    static func fuzzyMatch(queryTokens: [String], targetTokens: [String]) -> Bool {
        let limitedQueryTokens = queryTokens
            .map { $0.lowercased() }
            .filter { $0.count >= 2 && $0.count <= 32 }
            .prefix(4)
        let limitedTargetTokens = targetTokens
            .map { $0.lowercased() }
            .filter { $0.count >= 2 && $0.count <= 48 }
            .prefix(80)

        guard !limitedQueryTokens.isEmpty, !limitedTargetTokens.isEmpty else { return false }

        for qToken in limitedQueryTokens {
            let maxDist = maxDistance(for: qToken)
            var matched = false
            for tToken in limitedTargetTokens {
                // 先试精确包含
                if tToken.contains(qToken) {
                    matched = true
                    break
                }
                // 再试编辑距离
                if levenshteinDistance(qToken, tToken) <= maxDist {
                    matched = true
                    break
                }
            }
            // 也尝试在完整 target 字符串中查找
            if !matched {
                for tToken in limitedTargetTokens {
                    let dist = levenshteinDistance(qToken, String(tToken.prefix(qToken.count + maxDist)))
                    if dist <= maxDist { matched = true; break }
                }
            }
            if !matched { return false }
        }
        return true
    }
}
