import Foundation
import NaturalLanguage

/// 长句拆分：6词+句子打散为单词，停用词丢弃，词形还原。
enum SentenceSplitter {
    private static let minWordsToSplit = 6

    private static let stopWords: Set<String> = [
        "a", "an", "the",
        "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having",
        "do", "does", "did", "doing",
        "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their",
        "this", "that", "these", "those",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "about", "after", "before", "during", "over", "under", "up", "down",
        "and", "but", "or", "nor", "not", "so", "if", "than", "then", "also", "just",
        "very", "too", "only", "all", "each", "every", "both", "few", "more",
        "most", "other", "some", "such", "no", "any",
        "there", "here", "when", "where", "why", "how", "which", "who", "whom",
    ]

    /// 拆分结果：单词列表 + 原句
    struct SplitResult {
        let words: [String]       // 词形还原后的单词（去重、去停用词）
        let originalSentence: String
    }

    /// 判断是否需要拆分
    static func shouldSplit(_ text: String) -> Bool {
        splitIfNeeded(text) != nil
    }

    /// 需要拆分时返回结果，否则返回 nil（避免重复 tokenize）
    static func splitIfNeeded(_ text: String) -> SplitResult? {
        let tokenizer = NLTokenizer(unit: .word)
        let tokens = tokenize(text, with: tokenizer)
        guard tokens.count >= minWordsToSplit else { return nil }

        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagger = NLTagger(tagSchemes: [.lemma])
        let meaningful = tokens
            .filter { !stopWords.contains($0.lowercased()) }
            .map { lemmatize($0, with: tagger).lowercased() }
            .filter { $0.count >= 2 }

        var seen = Set<String>()
        let unique = meaningful.filter { seen.insert($0).inserted }

        return SplitResult(words: Array(unique), originalSentence: original)
    }

    /// 词形还原
    static func lemmatize(_ word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        return lemmatize(word, with: tagger)
    }

    static func lemmatize(_ word: String, with tagger: NLTagger) -> String {
        tagger.string = word
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        if let lemma = tag?.rawValue {
            return lemma
        }
        return word
    }

    // MARK: - Private

    private static func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        return tokenize(text, with: tokenizer)
    }

    private static func tokenize(_ text: String, with tokenizer: NLTokenizer) -> [String] {
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map {
            String(text[$0]).trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
    }
}
