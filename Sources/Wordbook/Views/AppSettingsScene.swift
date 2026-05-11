import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct AppSettingsScene: View {
    @EnvironmentObject private var store: WordbookStore
    @AppStorage(UserDefaultsKey.clipboardAutoCaptureEnabled.rawValue) private var clipboardAutoCaptureEnabled = true
    @AppStorage(UserDefaultsKey.defaultClipboardSource.rawValue) private var defaultClipboardSource = "Bob"
    @AppStorage(UserDefaultsKey.defaultClipboardTags.rawValue) private var defaultClipboardTags = ""
    @AppStorage(UserDefaultsKey.autoTranslationEnabled.rawValue) private var autoTranslationEnabled = true
    @AppStorage(UserDefaultsKey.dictionaryEnhancementEnabled.rawValue) private var dictionaryEnhancementEnabled = true
    @AppStorage(UserDefaultsKey.preferCachedDefinitions.rawValue) private var preferCachedDefinitions = true
    @AppStorage(UserDefaultsKey.reviewReminderEnabled.rawValue) private var reviewReminderEnabled = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(UserDefaultsKey.reviewReminderHour.rawValue) private var reviewReminderHour = 9
    @AppStorage(UserDefaultsKey.reviewReminderMinute.rawValue) private var reviewReminderMinute = 0
    @AppStorage(UserDefaultsKey.dailyReviewGoal.rawValue) private var dailyReviewGoal = 10
    @State private var showImporter = false

    private let appVersion = "1.2.1"

    var body: some View {
        content
            .onAppear { updateReminder() }
    }

    private var content: some View {
        TabView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("后台自动记录剪切板", isOn: $clipboardAutoCaptureEnabled)
                Text(ClipboardParser.autoIngestRulesDescription())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("默认来源", text: $defaultClipboardSource)
                TextField("默认标签（逗号分隔）", text: $defaultClipboardTags)

                Divider()

                HStack {
                    Text("每日复习目标")
                    Spacer()
                    Picker("", selection: $dailyReviewGoal) {
                        ForEach([3, 5, 10, 15, 20, 30, 50], id: \.self) { n in
                            Text("\(n) 条").tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                Text("达到目标后侧边栏进度条会变绿。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("定时提醒复习", isOn: $reviewReminderEnabled)
                if reviewReminderEnabled {
                    HStack {
                        Text("每天")
                        Picker("", selection: $reviewReminderHour) {
                            ForEach(7...22, id: \.self) { h in
                                Text(String(format: "%02d:00", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text("提醒")
                    }
                    .onChange(of: reviewReminderEnabled) { _ in updateReminder() }
                    .onChange(of: reviewReminderHour) { _ in updateReminder() }
                }

                Divider()

                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Divider()

                Button("清理噪音词条") {
                    let removed = store.removeNoiseEntries()
                    if removed > 0 {
                        store.noticeMessage = "已清理 \(removed) 条噪音词条"
                    } else {
                        store.noticeMessage = "没有发现噪音词条"
                    }
                }
                .buttonStyle(.bordered)
                Text("删除误收入的纯中文、停用词、URL、代码等无效条目。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .padding()
            .tabItem { Label("通用", systemImage: "gear") }

            VStack(alignment: .leading, spacing: 16) {
                Toggle("自动补齐翻译", isOn: $autoTranslationEnabled)
                Toggle("词典释义增强", isOn: $dictionaryEnhancementEnabled)
                Toggle("优先使用缓存释义", isOn: $preferCachedDefinitions)
                Text("三源翻译引擎并行：MyMemory + Lingva + LibreTranslate。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .tabItem { Label("翻译", systemImage: "globe") }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("数据文件")
                        .font(.headline)
                Text(store.storageFilePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                HStack(spacing: 8) {
                    Button("清理噪音词条") {
                        let removed = store.removeNoiseEntries()
                        if removed > 0 {
                            store.noticeMessage = "已清理 \(removed) 条噪音词条"
                        } else {
                            store.noticeMessage = "没有发现噪音词条"
                        }
                    }
                    Button("导入 JSON") { showImporter = true }
                    Button("导出 JSON") {
                        store.saveImmediately()
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.json]
                        panel.nameFieldStringValue = "wordbook-export.json"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                let data = try store.exportEntriesData()
                                try data.write(to: url)
                                store.noticeMessage = "导出成功"
                            } catch {
                                store.errorMessage = "导出失败：\(error.localizedDescription)"
                            }
                        }
                    }
                }
                    Button("导出 Anki") {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.tabSeparatedText]
                        panel.nameFieldStringValue = "wordbook-anki.tsv"
                        if panel.runModal() == .OK, let url = panel.url {
                            do {
                                let text = store.ankiExportText()
                                try text.write(to: url, atomically: true, encoding: .utf8)
                                store.noticeMessage = "Anki 导出成功"
                            } catch {
                                store.errorMessage = "导出失败：\(error.localizedDescription)"
                            }
                        }
                    }
                    Divider()

                    Text("历史快照（每天自动保存，保留 30 天）")
                        .font(.headline)
                    HStack {
                        Button("立即快照") { store.saveSnapshotNow() }
                        Spacer()
                    }
                    let snapshots = store.availableSnapshots()
                    if snapshots.isEmpty {
                        Text("暂无快照")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        List(snapshots) { snap in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(snap.displayName)
                                        .font(.callout)
                                    Text("\(snap.entryCount) 条词条")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("恢复") {
                                    do {
                                        try store.restoreFromSnapshot(id: snap.id)
                                    } catch {
                                        store.errorMessage = "恢复失败：\(error.localizedDescription)"
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(height: 120)
                    }

                    Text("导入会覆盖当前列表。请先导出备份。Anki 格式为 TSV。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .tabItem { Label("数据", systemImage: "externaldrive") }
        }
        .frame(width: 560, height: 480)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    try store.importEntries(from: data)
                } catch {
                    store.errorMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func updateReminder() {
        if reviewReminderEnabled {
            ReviewReminderService.scheduleDaily(hour: reviewReminderHour, minute: reviewReminderMinute)
        } else {
            ReviewReminderService.cancel()
        }
    }
}
