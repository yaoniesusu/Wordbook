import Foundation

/// 从剪切板文本解析中英，兼容 Bob 等工具常见输出格式。
enum ClipboardParser {
    /// 读取系统剪切板纯文本。
    static func pasteboardPlainText() -> String? {
        SystemPasteboardReader().plainText()
    }

    /// 将剪切板内容解析为词条字段；双语内容会自动识别中英文顺序。
    static func parseBobStyle(_ raw: String) -> (english: String, chinese: String, example: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "", "") }

        // Tab 分隔：英文\t中文
        if let tabParts = splitOnce(trimmed, separators: ["\t"]) {
            return normalizedPair(tabParts.0, tabParts.1, example: "")
        }

        // 常见分隔符：— – - ⇄ ↔
        let dashSeparators = [" ⇄ ", " ↔ ", " — ", " – ", " - ", "——", "—"]
        for sep in dashSeparators {
            if let pair = splitOnce(trimmed, literal: sep) {
                return normalizedPair(pair.0, pair.1, example: "")
            }
        }

        // 多行：首行英文、次行中文；若超过两行，第三行起合并为例句
        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if lines.count >= 2 {
            let rest = lines.dropFirst(2).joined(separator: "\n")
            return normalizedPair(lines[0], lines[1], example: rest)
        }

        if containsHan(trimmed), !containsLatin(trimmed) {
            return ("", trimmed, "")
        }
        return (trimmed, "", "")
    }

    /// 判断是否适合「无感」自动写入单词本：长度合理、排除典型非学习内容，支持英文或中文词条。
    static func shouldAutoIngest(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 4000 else { return false }

        if looksLikeSingleURL(trimmed) { return false }
        if looksLikeGarbledText(trimmed) { return false }
        if looksLikeNoise(trimmed) { return false }

        let wordCount = tokenCount(in: trimmed)
        guard wordCount <= 15 else { return false }

        let lineCount = trimmed.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        guard lineCount <= 4 else { return false }

        let parsed = parseBobStyle(trimmed)
        let en = parsed.english.trimmingCharacters(in: .whitespacesAndNewlines)
        let zh = parsed.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !en.isEmpty || !zh.isEmpty else { return false }
        guard containsLatin(en) || containsHan(zh) else { return false }
        guard en.isEmpty || isPlausibleVocabularyText(en) else { return false }
        guard zh.isEmpty || isPlausibleChineseText(zh) else { return false }

        return true
    }

    /// 检查单个英文文本是否为噪音（供清理旧数据使用）
    static func isNoiseText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if looksLikeSingleURL(trimmed) { return true }
        if looksLikeGarbledText(trimmed) { return true }
        if looksLikeNoise(trimmed) { return true }
        // 单字符
        if trimmed.count <= 1 { return true }
        // 纯数字 / 纯符号
        if Double(trimmed) != nil { return true }
        if !trimmed.contains(where: \.isLetter) { return true }
        // 中文被错误当作文本（只含汉字不含拉丁字母）
        if containsHan(trimmed), !containsLatin(trimmed) { return true }
        // 长句（6 个单词以上，应该被拆分而非独立收录）
        let wordCount = tokenCount(in: trimmed)
        if wordCount >= 6 { return true }
        // 常见停用词单独收录无意义
        if isStopWord(trimmed) { return true }
        // 过长无空格字符串（hash、token 等）
        if trimmed.count > 40, !trimmed.contains(" ") { return true }
        return false
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "am", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "having", "do", "does", "did", "doing",
        "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their", "this", "that", "these", "those",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "about", "after", "before", "during", "over", "under", "up", "down",
        "and", "but", "or", "nor", "not", "so", "if", "than", "then", "also", "just",
        "very", "too", "only", "all", "each", "every", "both", "few", "more",
        "most", "other", "some", "such", "no", "any",
        "there", "here", "when", "where", "why", "how", "which", "who", "whom",
        "what", "now", "one", "two", "go", "get", "make", "like", "know", "take",
        "see", "come", "think", "look", "want", "give", "use", "find", "tell",
        "ask", "work", "seem", "feel", "try", "leave", "call", "keep", "let",
        "begin", "show", "hear", "play", "run", "move", "live", "believe",
        "hold", "bring", "happen", "write", "provide", "sit", "stand", "lose",
        "pay", "meet", "include", "continue", "set", "learn", "change", "lead",
        "understand", "watch", "follow", "stop", "create", "speak", "read",
        "allow", "add", "spend", "grow", "open", "walk", "win", "offer",
        "remember", "love", "consider", "appear", "buy", "wait", "serve",
        "die", "send", "expect", "build", "stay", "fall", "cut", "reach",
        "kill", "remain", "suggest", "raise", "pass", "sell", "require",
        "report", "decide", "pull", "though", "however", "therefore",
    ]

    private static func isStopWord(_ word: String) -> Bool {
        stopWords.contains(word.lowercased())
    }

    /// 检测乱码：包含替换字符、私有区字符、或有效文字占比过低。
    static func looksLikeGarbledText(_ s: String) -> Bool {
        // 包含 Unicode 替换字符 (U+FFFD)
        if s.contains("\u{FFFD}") { return true }

        let scalars = Array(s.unicodeScalars)
        guard !scalars.isEmpty else { return true }

        // 统计各类字符
        var meaningful = 0
        var punctuation = 0
        var control = 0
        var privateUse = 0

        for scalar in scalars {
            switch scalar.value {
            case 0xE000...0xF8FF,   // 私有使用区
                 0xF0000...0xFFFFD,
                 0x100000...0x10FFFD:
                privateUse += 1
            case 0x0000...0x001F,   // 控制字符 (不含空格)
                 0x007F...0x009F,
                 0x200B...0x200F,   // 零宽字符
                 0x2028...0x2029,   // 行分隔符
                 0xFEFF:            // BOM
                if scalar.value > 0x001F || scalar.value < 0x0020 {
                    control += 1
                }
            default:
                if CharacterSet.letters.contains(scalar)
                    || CharacterSet.decimalDigits.contains(scalar)
                    || scalar == UnicodeScalar(0x0020)  // 空格
                    || (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF)  // CJK
                    || (scalar.value >= 0x3400 && scalar.value <= 0x4DBF)  // CJK 扩展A
                    || (scalar.value >= 0x20000 && scalar.value <= 0x2A6DF) // CJK 扩展B
                {
                    meaningful += 1
                } else if CharacterSet.punctuationCharacters.contains(scalar)
                            || CharacterSet.symbols.contains(scalar) {
                    punctuation += 1
                }
            }
        }

        let total = scalars.count

        // 私有区字符占比 > 30%，视为乱码
        if Double(privateUse) / Double(total) > 0.3 { return true }

        // 控制字符占比 > 20%，视为乱码
        if Double(control) / Double(total) > 0.2 { return true }

        // 有效文字（字母+数字+中文+空格）占比 < 30%，视为乱码
        let meaningfulRatio = Double(meaningful) / Double(total)
        if meaningfulRatio < 0.3 { return true }

        // 标点符号占比 > 60%，视为乱码
        if Double(punctuation) / Double(total) > 0.6 { return true }

        return false
    }

    static func autoIngestRulesDescription() -> String {
        "自动收录要求：不超过 15 个词、4 行、4000 字符，且过滤网址/邮箱/UUID/路径/代码/命令/编号/错误码/菜单路径/键盘乱敲等噪音。纯英文自动补齐中文，纯中文自动补齐英文。"
    }

    /// 单行且为常见 http(s) 链接时不自动收录。
    static func looksLikeSingleURL(_ s: String) -> Bool {
        guard !s.contains("\n"), s.contains("://") else { return false }
        if URL(string: s) != nil { return true }
        return false
    }

    /// 检测无意义的噪音内容：网址、邮箱、代码、哈希、人名、金额、序列号等。
    static func looksLikeNoise(_ s: String) -> Bool {
        // ── 网络与协议 ──
        // URL（含磁力链接、种子、IPFS 等）
        if s.range(of: "https?://|ftp://|file://|ws://|wss://|magnet:\\?|ipfs://|ed2k://|aeskey:", options: .regularExpression) != nil { return true }
        // 邮箱
        if s.range(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", options: .regularExpression) != nil { return true }
        // 社交媒体句柄 (@username, #hashtag)
        if s.range(of: "[@#][A-Za-z0-9_]{2,30}\\b", options: .regularExpression) != nil { return true }
        // 裸域名 / www 链接
        if s.range(of: "\\b(www\\.)?[A-Za-z0-9-]+\\.(com|net|org|io|dev|app|cn|me|co|ai|edu|gov)(/[A-Za-z0-9._~:/?#\\[\\]@!$&'()*+,;=%-]*)?\\b", options: [.regularExpression, .caseInsensitive]) != nil { return true }

        // ── 标识符与加密 ──
        // UUID
        if s.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", options: .regularExpression) != nil { return true }
        // 长十六进制（哈希、种子 hash、加密货币地址）：≥32 位连续
        if s.range(of: "[0-9a-fA-F]{32,}", options: .regularExpression) != nil { return true }
        // Base64 编码（特征：字母数字 +/= 结尾，长度 > 40）
        if s.range(of: "^[A-Za-z0-9+/=]{40,}$", options: .regularExpression) != nil { return true }
        // JWT Token (eyJ... 开头，三段 . 分隔)
        if s.range(of: "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", options: .regularExpression) != nil { return true }
        // SSH 公钥 / PEM 头
        if s.range(of: "-----BEGIN (RSA |EC |OPENSSH |PGP )", options: .regularExpression) != nil { return true }
        // Bundle id / reverse-DNS 标识
        if s.range(of: "^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z_][A-Za-z0-9_-]*){2,}$", options: .regularExpression) != nil { return true }

        // ── 代码与标记语言 ──
        // 代码围栏或 shell 提示符
        if s.contains("```") || s.range(of: "^\\s*[$>%❯]\\s*\\S+", options: .regularExpression) != nil { return true }
        // 常见命令行片段
        if s.range(of: "^(git|swift|npm|pnpm|yarn|brew|curl|ssh|scp|rsync|python|python3|node|ruby|go|cargo|docker|kubectl|make|xcodebuild)\\b\\s+\\S+", options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // HTML/XML 标签
        if s.range(of: "</?[a-z]+[^>]*>", options: .regularExpression) != nil { return true }
        // 代码特征：花括号、分号密度高，或包含典型关键字
        if s.range(of: "(function|const |let |var |import |export |class |public |private |def |return |SELECT |INSERT |UPDATE |DELETE |func |struct |enum |protocol )", options: .regularExpression) != nil { return true }
        // 函数调用、赋值、常见属性访问或代码符号密度
        if s.range(of: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*\\([^)]*\\)", options: .regularExpression) != nil { return true }
        if s.range(of: "[A-Za-z_][A-Za-z0-9_]*\\s*(==|=|=>|->|::)\\s*\\S+", options: .regularExpression) != nil { return true }
        if symbolDensity(in: s) > 0.22, containsLatin(s) { return true }
        // JSON 特征
        if s.range(of: "^[\\{\\[]", options: .regularExpression) != nil && s.contains(":") && s.contains("\"") { return true }
        // Markdown 链接/图片语法
        if s.range(of: "\\[.+\\]\\(https?://", options: .regularExpression) != nil { return true }
        // 常见 TODO / 日志 / 错误码片段
        if s.range(of: "\\b(TODO|FIXME|MARK|ERROR|WARN|INFO|DEBUG|TRACE|HTTP\\s*[0-9]{3}|ERR_[A-Z0-9_]+)\\b", options: .regularExpression) != nil { return true }

        // ── 路径与系统 ──
        // 文件路径
        if s.range(of: "^[~/\\\\]|[A-Z]:\\\\|^\\w+:\\\\", options: .regularExpression) != nil { return true }
        if s.range(of: "\\b[\\w.-]+/[\\w./-]+\\b", options: .regularExpression) != nil { return true }
        if s.range(of: "\\b[\\w.-]+\\.(swift|js|ts|tsx|jsx|json|plist|md|txt|yml|yaml|html|css|py|sh|rb|go|rs|java|kt|c|cpp|h|m|mm)(:[0-9]+)?\\b", options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // 菜单/面包屑路径
        if s.range(of: "\\S+\\s*(>|›|→)\\s*\\S+", options: .regularExpression) != nil { return true }
        // 版本号
        if s.range(of: "\\bv?[0-9]+\\.[0-9]+\\.[0-9]+", options: .regularExpression) != nil { return true }
        // IP 地址
        if s.range(of: "\\b[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\b", options: .regularExpression) != nil { return true }

        // ── 序列号与凭证 ──
        // 产品编号/目录号：字母-数字格式 (DVDES-410, ABP-123) 或字母+数字混合 (mukd455, BBAN219)
        if s.range(of: "^[A-Za-z]{2,8}-[0-9]{2,5}$", options: .regularExpression) != nil { return true }
        if s.range(of: "^[A-Za-z]{3,8}[0-9]{2,4}$", options: .regularExpression) != nil { return true }
        // 常见影片番号 / 目录号变体：ABCD-123、ABC 00123、FC2-PPV-1234567、HEYZO-1234、1PON-123456_001
        if s.range(of: "^[A-Za-z]{2,8}[\\s_-]?[0-9]{2,6}$", options: .regularExpression) != nil { return true }
        if s.range(of: "^[A-Za-z]{2,6}-[A-Za-z]{2,6}-[0-9]{3,10}$", options: .regularExpression) != nil { return true }
        if s.range(of: "^[0-9][A-Za-z]{2,5}-[0-9]{5,8}(_[0-9]{2,4})?$", options: .regularExpression) != nil { return true }
        // 序列号/激活码 (XXXX-XXXX-XXXX 或 XXXX-XXXX-XXXX-XXXX)
        if s.range(of: "[A-Z0-9]{4,6}-[A-Z0-9]{4,6}-[A-Z0-9]{4,6}(-[A-Z0-9]{4,6})?", options: .regularExpression) != nil { return true }
        // ISBN
        if s.range(of: "ISBN(-1[03])?:?\\s*[0-9\\-]{10,}", options: .regularExpression) != nil { return true }

        // ── 联系与金融 ──
        // 电话号码（多种格式）
        if s.range(of: "(\\+\\d{1,3}[\\s-])?\\(?\\d{2,4}\\)?[\\s-]?\\d{2,4}[\\s-]?\\d{2,4}[\\s-]?\\d{2,4}", options: .regularExpression) != nil { return true }
        // 金额 ($1,234.56, ¥1000, €50)
        if s.range(of: "[$¥€£]\\s*[0-9,]+(\\.[0-9]{2})?", options: .regularExpression) != nil { return true }

        // ── 日期与时间 ──
        // 纯日期格式 (2024-01-15, 01/15/2024, 2024年1月15日)
        if s.range(of: "^[0-9]{2,4}[-/年][0-9]{1,2}[-/月][0-9]{1,2}[日号]?$", options: .regularExpression) != nil { return true }
        // 工单号 / ID 文案
        if s.range(of: "\\b(ID|Issue|Ticket|Task|PR|MR)\\s*[:#-]?\\s*[A-Z]*[0-9]{3,}\\b", options: [.regularExpression, .caseInsensitive]) != nil { return true }

        // ── 统计特征 ──
        let scalars = Array(s.unicodeScalars)
        let totalChars = scalars.count
        guard totalChars > 0 else { return true }

        var letterCount = 0
        var chineseCount = 0
        var digitCount = 0
        var upperCount = 0

        for scalar in scalars {
            if CharacterSet.letters.contains(scalar) {
                letterCount += 1
                if CharacterSet.uppercaseLetters.contains(scalar) { upperCount += 1 }
            } else if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                chineseCount += 1
            } else if CharacterSet.decimalDigits.contains(scalar) {
                digitCount += 1
            }
        }

        let meaningfulCount = letterCount + chineseCount
        let letterRatio = Double(letterCount) / Double(totalChars)
        let digitRatio = Double(digitCount) / Double(totalChars)
        let meaningfulRatio = Double(meaningfulCount) / Double(totalChars)

        // 数字占比 > 60% 且几乎没有字母/中文 → 编号、代码、金额
        if digitRatio > 0.6 && letterRatio < 0.1 && chineseCount == 0 { return true }
        // 纯数字 > 5 位 → ID、编号
        if meaningfulCount == 0 && digitCount >= 5 { return true }
        // 有效文字占比 < 25% → 符号噪音
        if meaningfulRatio < 0.25 { return true }
        // 含下划线或 camelCase 的短英文标识符通常是变量/键名
        if chineseCount == 0 && looksLikeCodeIdentifier(s) { return true }

        // ── 人名检测 ──
        // 纯英文（无中文），1-3 个单词，每个单词首字母大写 → 很可能是人名
        if chineseCount == 0 && letterCount > 0 {
            let words = s.split(separator: " ").filter { !$0.isEmpty }
            if words.count >= 2 && words.count <= 3 {
                let allCapitalized = words.allSatisfy { word in
                    guard let first = word.first, first.isUppercase else { return false }
                    // 排除全大写缩写（如 NASA, CIA）
                    let upperInWord = word.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
                    return upperInWord <= 1 || Double(upperInWord) / Double(word.count) <= 0.5
                }
                if allCapitalized && words.joined().count > 2 { return true }
            }
        }

        // ── 键盘乱敲 ──
        let smashPatterns = ["asdf", "fdsa", "qwer", "rewq", "zxcv", "vcxz",
                             "hjkl", "lkjh", "tyui", "iuyt", "bnm", "mnb",
                             "uiop", "poiu", "ghjk", "kjhg", "wert", "trew",
                             "sdfg", "gfds", "xcvb", "bvcx"]
        let lowercased = s.lowercased()
        for pattern in smashPatterns {
            if lowercased.contains(pattern) { return true }
        }

        // 同一字符连续重复 ≥ 6 次
        if s.range(of: "(.)\\1{5,}", options: .regularExpression) != nil { return true }

        return false
    }

    private static func isPlausibleVocabularyText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if looksLikeNoise(trimmed) || looksLikeGarbledText(trimmed) { return false }
        if tokenCount(in: trimmed) > 6 { return false }
        if trimmed.range(of: "[0-9_{}\\[\\]<>`=;|\\\\/]", options: .regularExpression) != nil { return false }
        let allowed = "^[A-Za-z][A-Za-z '\\u{2019}.-]*[A-Za-z.]$"
        return trimmed.range(of: allowed, options: .regularExpression) != nil
    }

    private static func isPlausibleChineseText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if looksLikeNoise(trimmed) || looksLikeGarbledText(trimmed) { return false }
        if trimmed.range(of: "[{}\\[\\]<>`=;|\\\\/]", options: .regularExpression) != nil { return false }
        return true
    }

    private static func tokenCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isPunctuation }.count
    }

    private static func symbolDensity(in text: String) -> Double {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return 1 }
        let symbols = scalars.filter {
            CharacterSet.symbols.contains($0)
                || CharacterSet.punctuationCharacters.contains($0)
                || "_=;{}[]<>|\\/".unicodeScalars.contains($0)
        }.count
        return Double(symbols) / Double(scalars.count)
    }

    private static func looksLikeCodeIdentifier(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil {
            return trimmed.contains("_")
                || trimmed.range(of: "[a-z][A-Z]", options: .regularExpression) != nil
                || trimmed.range(of: "[A-Z]{2,}", options: .regularExpression) != nil
        }
        if trimmed.range(of: "^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+$", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func splitOnce(_ s: String, literal sep: String) -> (String, String)? {
        guard let r = s.range(of: sep) else { return nil }
        let a = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        let b = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return (a, b)
    }

    private static func splitOnce(_ s: String, separators: [String]) -> (String, String)? {
        for sep in separators {
            if let p = splitOnce(s, literal: sep) { return p }
        }
        return nil
    }

    private static func normalizedPair(_ first: String, _ second: String, example: String) -> (english: String, chinese: String, example: String) {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsHan(a), containsLatin(b) {
            return (b, a, example)
        }
        return (a, b, example)
    }

    private static func containsLatin(_ s: String) -> Bool {
        s.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    private static func containsHan(_ s: String) -> Bool {
        s.range(of: "\\p{Han}", options: .regularExpression) != nil
    }
}
