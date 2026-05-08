# Wordbook (单词本)

macOS 生词本应用，Swift 5.9 + SwiftUI，Swift Package Manager 构建，macOS 13+。

## 架构

```
Sources/Wordbook/
├── WordbookApp.swift          # @main 入口，注册 UserDefaults 默认值，环境注入 WordbookStore
├── Models/
│   ├── VocabularyEntry.swift       # 核心数据模型：中英对照、例句、标签、复习状态
│   ├── DictionaryEntryCache.swift  # 词典缓存模型
│   ├── IngestHistoryItem.swift     # 收录历史
│   └── WordbookStats.swift         # 统计数据
├── Services/
│   ├── WordbookStore.swift         # @MainActor 中央状态管理：CRUD、复习逻辑、索引、JSON 持久化
│   ├── ClipboardParser.swift       # 剪切板文本解析（中英识别）+ 噪音过滤
│   ├── TranslationService.swift    # MyMemory 翻译 API（EN↔ZH）
│   ├── DictionaryLookupService.swift # FreeDictionary API 查词
│   ├── PasteboardReading.swift     # 系统剪切板读取协议
│   ├── StorageLocationResolver.swift # 数据目录解析
│   └── PlatformFeatures.swift      # 平台特性
└── Views/
    ├── ContentView.swift           # 主界面：NavigationSplitView + 工具栏 + 设置 sheet
    ├── EntryListView.swift         # 侧边栏词条列表
    ├── EntryDetailView.swift       # 词条详情编辑
    ├── DailyReviewView.swift       # 间隔重复复习
    ├── StatsView.swift             # 学习统计
    ├── ManualEntrySheet.swift      # 手动新增 sheet
    ├── SurfaceStyles.swift         # 通用 UI 样式
    └── UnavailablePlaceholderView.swift
```

## 核心设计

- **状态管理**：`WordbookStore` 是唯一真相源，通过 `@EnvironmentObject` 注入视图树
- **持久化**：JSON 文件存储于 `~/Library/Application Support/Wordbook/`，含自动备份
- **索引**：`entriesByID`、`entryIDsByNormalizedEnglish`、`searchIndex` 三个字典加速查询
- **剪切板**：1.15s 轮询 `NSPasteboard.changeCount`，经 `ClipboardParser.shouldAutoIngest` 多层过滤
- **复习算法**：间隔递增 [1, 3, 7, 14, 30] 天，reviewCount>=5 标为已掌握
- **翻译**：手动添加时若缺中文则调 MyMemory API 自动补齐，超时 8s

## 构建与运行

```bash
swift build
swift run
```

测试：
```bash
swift test
```

## 编码约定

- UI 文本使用中文
- 新功能优先在现有服务/视图中扩展，避免新建文件
- 翻译/词典等网络请求需设超时
- UserDefaults key 用 camelCase，注册默认值在 WordbookApp.init()
