import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// 主界面：导航栏筛选、列表与详情、工具栏入口。
struct ContentView: View {
    @EnvironmentObject private var store: WordbookStore
    @AppStorage(UserDefaultsKey.clipboardAutoCaptureEnabled.rawValue) private var clipboardAutoCaptureEnabled = true
    @AppStorage(UserDefaultsKey.defaultClipboardSource.rawValue) private var defaultClipboardSource = "Bob"
    @AppStorage(UserDefaultsKey.defaultClipboardTags.rawValue) private var defaultClipboardTags = ""
    @AppStorage(UserDefaultsKey.appearanceMode.rawValue) private var appearanceMode: AppAppearanceMode = .system
    @AppStorage(UserDefaultsKey.autoTranslationEnabled.rawValue) private var autoTranslationEnabled = true
    @AppStorage(UserDefaultsKey.dictionaryEnhancementEnabled.rawValue) private var dictionaryEnhancementEnabled = true
    @AppStorage(UserDefaultsKey.preferCachedDefinitions.rawValue) private var preferCachedDefinitions = true
    @State private var selection: UUID?
    @State private var filter: EntryFilter = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var pendingSearchTask: Task<Void, Never>?
    @State private var showManualEntry = false
    @State private var showStats = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var isAddingFromClipboard = false
    @State private var toast: ToastState?
    @StateObject private var konami = KonamiWatcher()
    @State private var showClearConfirmation = false
    @State private var sidebarEditMode = false
    @State private var newlyAddedIDs: Set<UUID> = []
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        macBody
    }

    private var macBody: some View {
        let entries = filteredEntries
        let ids = entries.map(\.id)

        return NavigationSplitView {
            sidebar(filteredEntries: entries)
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 400)
        } detail: {
            detailPane.id(selection)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    selection = nil
                } label: {
                    Label("今日学习", systemImage: "house")
                }
                .help("返回学习首页")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    addClipboardEntry()
                } label: {
                    if isAddingFromClipboard {
                        Label { Text("添加中") } icon: { ProgressView().controlSize(.small) }
                    } else {
                        Label("从剪切板添加", systemImage: "doc.on.clipboard")
                    }
                }
                .disabled(isAddingFromClipboard)
                .help("快捷键 ⌘⇧V")
                Button { showManualEntry = true } label: { Label("手动新增", systemImage: "plus") }
                Button { showReviewWindow() } label: { Label("复习", systemImage: "calendar") }
                Button { showStats = true } label: { Label("统计", systemImage: "chart.bar") }
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: { Label("设置", systemImage: "gearshape") }
                Menu {
                    Button("导入 JSON") { showImporter = true }
                    Button("导出 JSON") { openExporter() }
                } label: { Label("更多", systemImage: "ellipsis.circle") }
            }
        }
        .searchable(text: $searchText, prompt: "搜索英文、中文、标签或来源")
        .onReceive(NotificationCenter.default.publisher(for: .showManualEntry)) { _ in
            showManualEntry = true
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .sheet(isPresented: $showManualEntry) { ManualEntrySheet(isPresented: $showManualEntry).environmentObject(store) }
        .sheet(isPresented: $showStats) { StatsView(isPresented: $showStats).environmentObject(store) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { handleImport($0) }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json, defaultFilename: "wordbook-export") { handleExport($0) }
        .modifier(KonamiModifier(konami: konami, store: store, showClearConfirmation: $showClearConfirmation, selection: $selection))
        .onAppear { store.setClipboardAutoCaptureEnabled(clipboardAutoCaptureEnabled); konami.start() }
        .sheet(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { if !$0 { hasSeenOnboarding = true } }
        )) {
            OnboardingView(isPresented: Binding(
                get: { !hasSeenOnboarding },
                set: { if !$0 { hasSeenOnboarding = true } }
            ))
        }
        .onDisappear { konami.stop() }
        .onChange(of: clipboardAutoCaptureEnabled) { store.setClipboardAutoCaptureEnabled($0) }
        .onChange(of: searchText) { debounceSearch($0) }
        .onChange(of: ids) { newIDs in if let selection, !newIDs.contains(selection) { self.selection = nil } }
        .onChange(of: store.noticeMessage) { if let msg = $0 { showToast(message: msg, color: .green) } }
        .onChange(of: store.errorMessage) { if let msg = $0 { showToast(message: msg, color: .red) } }
        .overlay(alignment: .top) {
            if let toast {
                ToastView(message: toast.message, color: toast.color)
                    .padding(.top, 12).transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: toast?.id)
        .onDrop(of: [.plainText, .utf8PlainText], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func sidebar(filteredEntries: [VocabularyEntry]) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: AppTheme.Space.small) {
                HStack {
                    Text("单词本")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            sidebarEditMode.toggle()
                        }
                    } label: {
                        Label(sidebarEditMode ? "完成" : "选择", systemImage: sidebarEditMode ? "checkmark" : "checklist")
                    }
                    .buttonStyle(.borderless)
                    .help(sidebarEditMode ? "退出批量操作" : "批量选择与操作")
                }
                Picker("筛选", selection: $filter) {
                    ForEach(EntryFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Picker("排序", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .font(.body)
            }
            .padding(.horizontal, AppTheme.Space.large)
            .padding(.vertical, AppTheme.Space.medium)

            Button {
                showReviewWindow()
            } label: {
                sidebarProgressCard(stats: store.stats())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Space.large)
            .padding(.bottom, AppTheme.Space.medium)

            if hasSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("搜到 \(filteredEntries.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Space.large)
                .padding(.bottom, AppTheme.Space.xSmall)
                .transition(.opacity)
            }

            EntryListView(
                selection: $selection,
                filter: filter,
                searchText: debouncedSearchText,
                entries: filteredEntries,
                editMode: $sidebarEditMode
            )
            .environmentObject(store)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hasSearch)
    }

    @AppStorage(UserDefaultsKey.dailyReviewGoal.rawValue) private var dailyReviewGoal = 10

    private func sidebarProgressCard(stats: WordbookStats) -> some View {
        let progress = dailyReviewGoal > 0 ? min(Double(stats.reviewedTodayCount) / Double(dailyReviewGoal), 1.0) : 0

        return VStack(alignment: .leading, spacing: AppTheme.Space.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日目标")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(stats.reviewedTodayCount)/\(dailyReviewGoal)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(progress >= 1.0 ? .green : .accentColor)
                .controlSize(.small)

            HStack(spacing: 0) {
                sidebarMetric("到期", "\(stats.dueTodayCount)", tint: .orange)
                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, AppTheme.Space.small)
                sidebarMetric("连续", "\(stats.studyStreakDays)天", tint: .green)
            }
        }
        .padding(.horizontal, AppTheme.Space.medium)
        .padding(.vertical, AppTheme.Space.medium)
        .surfaceCard(
            cornerRadius: AppTheme.Radius.medium,
            material: .thinMaterial,
            strokeOpacity: AppTheme.Stroke.subtle,
            shadowOpacity: 0.012,
            shadowRadius: 4,
            shadowY: 1
        )
    }

    private func sidebarMetric(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selection {
            EntryDetailView(entryId: id, onEntryDeleted: { selection = nil })
                .environmentObject(store)
        } else {
            TodayLearningOverview(
                selection: $selection,
                startReview: showReviewWindow,
                showManualEntry: $showManualEntry
            )
                .environmentObject(store)
        }
    }

    private var filteredEntries: [VocabularyEntry] {
        store.filteredEntries(filter: filter, query: debouncedSearchText, sortOrder: sortOrder)
    }

    private var hasSearch: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var exportDocument: WordbookEntriesDocument {
        let data = (try? store.exportEntriesData()) ?? Data("[]".utf8)
        return WordbookEntriesDocument(data: data)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else {
            if case let .failure(error) = result {
                store.errorMessage = "导入失败：\(error.localizedDescription)"
            }
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            try store.importEntries(from: data)
        } catch {
            store.errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func handleExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            store.noticeMessage = "导出成功"
        case let .failure(error):
            store.errorMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func openExporter() {
        store.saveImmediately()
        showExporter = true
    }

    private func addClipboardEntry() {
        guard !isAddingFromClipboard else { return }
        isAddingFromClipboard = true
        let tags = tagTokens(from: defaultClipboardTags)
        let source = defaultClipboardSource.trimmingCharacters(in: .whitespaces)

        Task {
            await store.addFromClipboardAndWait(
                mergeTags: tags,
                sourceHint: source
            )
            isAddingFromClipboard = false
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let tags = tagTokens(from: defaultClipboardTags)
        let source = defaultClipboardSource.trimmingCharacters(in: .whitespaces)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let text = item as? String {
                        DispatchQueue.main.async {
                            store.addFromDroppedText(text, mergeTags: tags, sourceHint: source)
                        }
                    }
                }
            }
        }
    }

    private func debounceSearch(_ value: String) {
        pendingSearchTask?.cancel()
        pendingSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedSearchText = value
            }
        }
    }

    private func showToast(message: String, color: Color) {
        let newToast = ToastState(message: message, color: color)
        toast = newToast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if toast?.id == newToast.id {
                toast = nil
                store.noticeMessage = nil
                store.errorMessage = nil
            }
        }
    }

    private func showReviewWindow() {
        ReviewWindowPresenter.shared.show(store: store)
    }
}

@MainActor
private final class ReviewWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = ReviewWindowPresenter()

    private var window: NSWindow?

    func show(store: WordbookStore) {
        if let window {
            recenter(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = DailyReviewView(
            isPresented: Binding(
                get: { true },
                set: { isPresented in
                    if !isPresented {
                        ReviewWindowPresenter.shared.close()
                    }
                }
            )
        )
        .environmentObject(store)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "每日复习"
        window.contentViewController = NSHostingController(rootView: view)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 500)
        recenter(window)

        window.delegate = self
        self.window = window
        window.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.animator().alphaValue = 1
    }

    private func recenter(_ window: NSWindow) {
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let size = window.frame.size
            let x = mainFrame.midX - size.width / 2
            let y = mainFrame.midY - size.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct ToastState: Identifiable {
    let id = UUID()
    let message: String
    let color: Color
}

struct ToastView: View {
    let message: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: color == .red ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            Text(message)
                .lineLimit(2)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

private func tagTokens(from raw: String) -> [String] {
    raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

private struct TodayLearningOverview: View {
    @EnvironmentObject private var store: WordbookStore
    @Binding var selection: UUID?
    let startReview: () -> Void
    @Binding var showManualEntry: Bool
    @ScaledMetric private var titleSize: CGFloat = 32

    var body: some View {
        let stats = store.stats()
        let dueNow = store.dueEntries()
        let dueToday = Array(store.todayDueEntries().prefix(4))
        let difficult = store.difficultEntries(limit: 4)
        let newEntries = store.recentNewEntries(limit: 4)
        let hasReviewItems = !dueNow.isEmpty || !difficult.isEmpty

        VStack(alignment: .leading, spacing: AppTheme.Space.section) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: AppTheme.Space.small) {
                    Text("今日学习")
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    Text("先清到期词，再回看难词，最后补新词。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    startReview()
                } label: {
                    Label("开始复习", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasReviewItems)
            }

            HStack(spacing: AppTheme.Space.medium) {
                dashboardMetric("今天到期", "\(stats.dueTodayCount)", systemImage: "calendar.badge.clock")
                dashboardMetric("今日已复习", "\(stats.reviewedTodayCount)", systemImage: "checkmark.circle")
                dashboardMetric("连续复习", "\(stats.studyStreakDays) 天", systemImage: "flame")
                dashboardMetric("掌握率", stats.masteryRateText, systemImage: "chart.pie")
            }

            HStack(alignment: .top, spacing: AppTheme.Space.medium) {
                learningSection(
                    title: "到期词",
                    systemImage: "calendar.badge.clock",
                    entries: dueToday,
                    emptyTitle: "今天没有到期词条",
                    emptyMessage: "可以新增一些词条，或者稍后再回来。"
                )
                learningSection(
                    title: "难词回看",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                    entries: difficult,
                    emptyTitle: "暂无难词",
                    emptyMessage: "忘记或吃力的词会在这里聚起来。"
                )
                learningSection(
                    title: "今日新增",
                    systemImage: "plus.circle",
                    entries: newEntries,
                    emptyTitle: "今天还没新增",
                    emptyMessage: "手动添加或复制英文后会出现在这里。"
                )
            }
            .frame(maxHeight: 276)

            HStack {
                Button {
                    showManualEntry = true
                } label: {
                    Label("手动新增词条", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            Spacer()
        }
        .padding(AppTheme.Space.page)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: stats.dueTodayCount)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: stats.reviewedTodayCount)
    }

    private func dashboardMetric(_ title: String, _ value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous))
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: AppTheme.Size.metricCardHeight)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
    }

    private func learningSection(
        title: String,
        systemImage: String,
        entries: [VocabularyEntry],
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.medium) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if entries.isEmpty {
                VStack(spacing: AppTheme.Space.small) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(emptyTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(emptyMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 176)
            } else {
                VStack(spacing: AppTheme.Space.small) {
                    ForEach(entries) { entry in
                        Button {
                            selection = entry.id
                        } label: {
                            compactEntryRow(entry, systemImage: markerIcon(for: entry))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: AppTheme.Size.sectionCardMinHeight, alignment: .topLeading)
        .padding(AppTheme.Space.cardPadding)
        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
    }

    private func compactEntryRow(_ entry: VocabularyEntry, systemImage: String) -> some View {
        HStack(spacing: AppTheme.Space.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: AppTheme.Space.xSmall) {
                Text(entry.english)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(entry.chinese.isEmpty ? "待补充释义" : entry.chinese)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, AppTheme.Space.rowHorizontal)
        .padding(.vertical, AppTheme.Space.rowVertical)
        .frame(minHeight: AppTheme.Size.compactRowHeight)
        .insetRowBackground()
    }

    private func markerIcon(for entry: VocabularyEntry) -> String {
        if entry.lastReviewedAt == nil {
            return "leaf"
        }
        if entry.reviewCount == 0 {
            return "arrow.counterclockwise"
        }
        return "text.book.closed"
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest, alphabetical, dueFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "最新"
        case .alphabetical: return "A-Z"
        case .dueFirst: return "待复习优先"
        }
    }
}

enum EntryFilter: String, CaseIterable, Identifiable {
    case all, favorites, unmastered, mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .favorites: return "收藏"
        case .unmastered: return "未掌握"
        case .mastered: return "已掌握"
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct KonamiModifier: ViewModifier {
    @ObservedObject var konami: KonamiWatcher
    let store: WordbookStore
    @Binding var showClearConfirmation: Bool
    @Binding var selection: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: konami.triggered) { newValue in
                if newValue {
                    showClearConfirmation = true
                    konami.triggered = false
                }
            }
            .confirmationDialog("清空单词本？", isPresented: $showClearConfirmation) {
                Button("清空全部词条", role: .destructive) {
                    let allIDs = Set(store.filteredEntries(filter: .all, query: "").map(\.id))
                    store.delete(ids: allIDs)
                    selection = nil
                    store.noticeMessage = "已清空所有词条"
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这将永久删除单词本中的全部词条，不可恢复。")
            }
    }
}

private struct OnboardingView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue.gradient)
                Text("欢迎使用单词本")
                    .font(.title.weight(.bold))
                Text("自动收录 + 间隔复习，轻松积累词汇")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "doc.on.clipboard",
                    color: .blue,
                    title: "剪切板自动收录",
                    description: "复制任意英文单词或短语，应用会自动识别并收录。支持 Bob 格式（英文 + 中文）。"
                )
                featureRow(
                    icon: "calendar.badge.clock",
                    color: .orange,
                    title: "间隔重复复习",
                    description: "基于 SM-2 算法，在遗忘临界点安排复习。支持正常、反向、拼写、挖空四种模式。"
                )
                featureRow(
                    icon: "plus.circle",
                    color: .green,
                    title: "手动添加词条",
                    description: "点击 + 按钮手动录入，支持自动补齐翻译和词典释义。"
                )
                featureRow(
                    icon: "gearshape",
                    color: .gray,
                    title: "随时调整设置",
                    description: "在设置中可调整剪切板来源、每日复习目标、翻译开关等。"
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("开始使用")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 80)
            .padding(.bottom, 32)
        }
        .frame(width: 520, height: 560)
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

final class KonamiWatcher: ObservableObject {
    @Published var triggered = false
    private var index = 0
    private let sequence: [NSEvent.SpecialKey] = [.upArrow, .upArrow, .downArrow, .downArrow, .leftArrow, .rightArrow, .leftArrow, .rightArrow]
    private var monitor: Any?

    func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) {
        guard sequence.indices.contains(index) else { index = 0; return }
        if event.specialKey == sequence[index] {
            index += 1
            if index >= sequence.count {
                index = 0
                triggered = true
            }
        } else {
            index = 0
            if event.specialKey == sequence[0] { index = 1 }
        }
    }
}
