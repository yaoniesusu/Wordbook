import SwiftUI

/// 单条详情：优先呈现学习内容，编辑能力收进次级区域。
struct EntryDetailView: View {
    @EnvironmentObject private var store: WordbookStore
    let entryId: UUID
    var onEntryDeleted: (() -> Void)?

    @State private var draft: VocabularyEntry?
    @State private var savedDraft: VocabularyEntry?
    @State private var tagsField = ""
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @AppStorage("dictionaryEnhancementEnabled") private var dictionaryEnhancementEnabled = true
    @ScaledMetric private var detailWordSize: CGFloat = 38
    @ScaledMetric private var chineseDisplaySize: CGFloat = 26

    var body: some View {
        Group {
            if draft != nil {
                detailContent
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("加载中…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: entryId) { reloadFromStore() }
        .onChange(of: store.entryVersion(for: entryId)) { _ in
            syncFromStore(store.entry(id: entryId), resetTransientState: false)
        }
        .task(id: draft?.english) {
            guard let draft else { return }
            await store.ensureDictionaryEntry(for: draft)
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Space.section) {
                headerCard
                learningCard
                statusPanel
                editPanel
                dangerPanel
            }
            .padding(.horizontal, AppTheme.Space.page)
            .padding(.vertical, AppTheme.Space.section)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("详情")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Label("收藏", systemImage: (draft?.isFavorite ?? false) ? "star.fill" : "star")
                }
                Button {
                    toggleMastered()
                } label: {
                    Label("掌握", systemImage: (draft?.isMastered ?? false) ? "checkmark.seal.fill" : "checkmark.seal")
                }
                Button("保存") { persist() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!hasUnsavedChanges)
            }
        }
        .confirmationDialog("删除词条？", isPresented: $showDeleteConfirmation) {
            Button("删除此条", role: .destructive) {
                onEntryDeleted?()
                store.delete(ids: [entryId])
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会从单词本中移除“\(primaryTitle)”。")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.large) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(primaryTitle)
                    .font(.system(size: detailWordSize, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                Button {
                    SpeechService.speak(primaryTitle)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("朗读单词")
            }

            HStack(spacing: 16) {
                metadataLabel(statusLabel, systemImage: statusIcon)
                if draft?.isFavorite == true {
                    metadataLabel("收藏", systemImage: "star.fill")
                }
                metadataLabel("下次 \(nextReviewLabel)", systemImage: "calendar")
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xLarge) {
            Text("释义")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            dictionaryDefinitionSection

            if !(draft?.exampleSentence.isEmpty ?? true) {
                Divider().padding(.vertical, 6)
                Text("例句 / 上下文")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(draft?.exampleSentence ?? "")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineSpacing(6)
                relatedEntriesView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .regularMaterial)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                statTile("复习次数", "\(draft?.reviewCount ?? 0)")
                statTile("最近复习", lastReviewedLabel)
                statTile("创建时间", createdAtLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
    }

    private var editPanel: some View {
        DisclosureGroup("编辑信息", isExpanded: $showEditor) {
            VStack(alignment: .leading, spacing: 12) {
                if hasUnsavedChanges {
                    Label("有未保存修改", systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                TextField("英文", text: stringBinding(\.english), axis: .vertical)
                    .lineLimit(2 ... 6)
                    .font(.body)
                TextField("中文", text: stringBinding(\.chinese), axis: .vertical)
                    .lineLimit(2 ... 8)
                    .font(.body)
                TextField("例句 / 上下文", text: stringBinding(\.exampleSentence), axis: .vertical)
                    .lineLimit(3 ... 12)
                    .font(.body)
                TextField("标签（逗号分隔）", text: $tagsField)
                    .font(.body)
                tagSuggestions
                TextField("来源", text: stringBinding(\.source))
                    .font(.body)
                HStack {
                    Toggle("收藏", isOn: boolBinding(\.isFavorite))
                    Toggle("已掌握", isOn: boolBinding(\.isMastered))
                }
                Button {
                    persist()
                } label: {
                    Label("保存修改", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges)
            }
            .textFieldStyle(.roundedBorder)
            .padding(.top, 12)
        }
        .font(.callout)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
    }

    private var dangerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("危险操作")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Button("删除此条", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial, strokeOpacity: AppTheme.Stroke.subtle, shadowOpacity: 0.015, shadowRadius: 5, shadowY: 2)
    }

    private func metadataLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
    }

    @ViewBuilder
    private var dictionaryDefinitionSection: some View {
        if dictionaryEnhancementEnabled, let english = draft?.english, let dictionary = store.dictionaryEntry(for: english) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let phonetic = dictionary.phonetic, !phonetic.isEmpty {
                        Text(phonetic)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        guard let draft else { return }
                        store.refreshDictionary(for: draft)
                    } label: {
                        Label("刷新释义", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }

                // 词条的中文翻译作为主含义
                if let chinese = draft?.chinese, !chinese.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(chinese)
                            .font(.system(size: chineseDisplaySize, weight: .regular))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineSpacing(8)
                        translationSourceBadge
                    }
                    .padding(AppTheme.Space.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetPill(cornerRadius: AppTheme.Radius.medium, tint: .accentColor, isActive: true)
                }

                ForEach(dictionary.meanings) { meaning in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(meaning.partOfSpeech)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(Array(meaning.definitions.enumerated()), id: \.element.id) { index, definition in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(index + 1). \(definition.englishDefinition)")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                if let example = definition.example, !example.isEmpty {
                                    Text(example)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !definition.synonyms.isEmpty {
                                    Text("近义：\(definition.synonyms.joined(separator: ", "))")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if index != meaning.definitions.count - 1 {
                                Divider().padding(.top, 4)
                            }
                        }
                    }
                    .padding(AppTheme.Space.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insetRowBackground()
                    if meaning.id != dictionary.meanings.last?.id {
                        Divider()
                    }
                }
            }
        } else if let english = draft?.english, store.isDictionaryLoading(for: english) {
            ProgressView("词典释义加载中…")
                .font(.callout)
        } else if let english = draft?.english, let message = store.dictionaryError(for: english) {
            VStack(alignment: .leading, spacing: 8) {
                fallbackChineseText
                Text("词典释义暂不可用：\(message)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    guard let draft else { return }
                    store.refreshDictionary(for: draft)
                } label: {
                    Label("重新查询词典", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
        } else {
            fallbackChineseText
        }
    }

    private var fallbackChineseText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((draft?.chinese.isEmpty ?? true) ? "暂无中文释义" : draft?.chinese ?? "")
                .font(.system(size: chineseDisplaySize, weight: .regular, design: .default))
                .foregroundStyle((draft?.chinese.isEmpty ?? true) ? .secondary : .primary)
                .textSelection(.enabled)
                .lineSpacing(8)
        }
        .padding(AppTheme.Space.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetPill(cornerRadius: AppTheme.Radius.medium, tint: .accentColor, isActive: !(draft?.chinese.isEmpty ?? true))
    }

    private var statusLabel: String {
        guard let d = draft else { return "学习中" }
        if d.isMastered { return "已掌握" }
        if d.reviewCount == 0 && d.lastReviewedAt == nil { return "未复习" }
        return "学习中"
    }
    private var statusIcon: String {
        guard let d = draft else { return "book" }
        if d.isMastered { return "checkmark.seal.fill" }
        if d.reviewCount == 0 && d.lastReviewedAt == nil { return "leaf" }
        return "book"
    }

    private var primaryTitle: String {
        draft?.english.isEmpty == false ? draft?.english ?? "" : "未命名词条"
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.medium)
        .insetRowBackground()
    }

    private func stringBinding(_ keyPath: WritableKeyPath<VocabularyEntry, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                if var d = draft {
                    d[keyPath: keyPath] = newValue
                    draft = d
                }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<VocabularyEntry, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? false },
            set: { newValue in
                if var d = draft {
                    d[keyPath: keyPath] = newValue
                    draft = d
                }
            }
        )
    }

    private func reloadFromStore() {
        if hasUnsavedChanges { persist() }
        syncFromStore(store.entry(id: entryId), resetTransientState: true)
    }

    private func syncFromStore(_ entry: VocabularyEntry?, resetTransientState: Bool) {
        guard let e = entry else {
            draft = nil
            savedDraft = nil
            return
        }

        if !resetTransientState, hasUnsavedChanges {
            savedDraft = e
            return
        }

        if !resetTransientState, draft == e, savedDraft == e {
            return
        }

        draft = e
        savedDraft = e
        tagsField = e.tags.joined(separator: ", ")
        if resetTransientState {
            showEditor = false
        }
    }

    private func persist() {
        guard var d = draft else { return }
        d.tags = tagsField.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft = d
        savedDraft = d
        store.update(d)
    }

    private func toggleFavorite() {
        guard var d = draft else { return }
        d.isFavorite.toggle()
        draft = d
        store.update(d)
        savedDraft = d
    }

    private func toggleMastered() {
        guard var d = draft else { return }
        d.isMastered.toggle()
        draft = d
        store.update(d)
        savedDraft = d
    }

    private var nextReviewLabel: String {
        guard let nextReviewAt = draft?.nextReviewAt else { return "未安排" }
        return nextReviewAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var lastReviewedLabel: String {
        guard let lastReviewedAt = draft?.lastReviewedAt else { return "未复习" }
        return lastReviewedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var createdAtLabel: String {
        (draft?.createdAt ?? .distantPast).formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var translationSourceBadge: some View {
        if let entryId = draft?.id, let meta = store.translationMetadata[entryId] {
            HStack(spacing: 4) {
                Image(systemName: meta.confidence == .high ? "checkmark.shield" : "info.circle")
                    .font(.caption)
                Text("\(meta.sourceName) · \(meta.confidence.rawValue)")
                    .font(.caption)
            }
            .foregroundStyle(meta.confidence == .high ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        TagSuggestionBar(tagsField: tagsField, allTags: store.allTags) { tag in
            var parts = tagsField.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if !parts.isEmpty { parts[parts.count - 1] = tag }
            tagsField = parts.joined(separator: ", ") + ", "
        }
    }

    @ViewBuilder
    private var relatedEntriesView: some View {
        if let draft, !draft.exampleSentence.isEmpty {
            let related = store.relatedEntries(for: draft)
            if !related.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("收录例句（\(related.count) 条关联）")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(related) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(entry.english)
                                .font(.callout)
                            if !entry.chinese.isEmpty {
                                Text(entry.chinese)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var hasUnsavedChanges: Bool {
        guard var current = draft, let savedDraft else { return false }
        current.tags = parsedTags
        return current != savedDraft
    }

    private var parsedTags: [String] {
        tagsField
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
