import SwiftUI

extension Notification.Name {
    static let showManualEntry = Notification.Name("showManualEntry")
}

@main
struct WordbookApp: App {
    @StateObject private var store = WordbookStore()

    init() {
        UserDefaults.standard.register(defaults: [
            .clipboardAutoCaptureEnabled: true,
            .defaultClipboardSource: "Bob",
            .defaultClipboardTags: "",
            .appearanceMode: AppAppearanceMode.system.rawValue,
            .autoTranslationEnabled: true,
            .dictionaryEnhancementEnabled: true,
            .preferCachedDefinitions: true,
            .reviewReminderEnabled: false,
            .reviewReminderHour: 9,
            .reviewReminderMinute: 0,
        ])
        ReviewReminderService.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.saveImmediately()
                }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("文件") {
                Button("手动新增") {
                    NotificationCenter.default.post(name: .showManualEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Divider()
                Button("导入 JSON") {
                    store.noticeMessage = "请在设置中导入"
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("手动从剪切板添加") {
                    store.addFromClipboard(
                        mergeTags: (UserDefaults.standard.string(forKey: .defaultClipboardTags) ?? "")
                            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                        sourceHint: UserDefaults.standard.string(forKey: .defaultClipboardSource) ?? ""
                    )
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .undoRedo) {
                Button("撤销") {
                    store.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
            }
        }

        Settings {
            AppSettingsScene()
                .environmentObject(store)
        }

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                let stats = store.stats()
                HStack {
                    Label("到期 \(stats.dueTodayCount) 个", systemImage: "calendar.badge.clock")
                    Spacer()
                }
                HStack {
                    Label("已复习 \(stats.reviewedTodayCount) 个", systemImage: "checkmark.circle")
                    Spacer()
                }
                HStack {
                    Label("连续 \(stats.studyStreakDays) 天", systemImage: "flame")
                    Spacer()
                }

                Divider()

                Button("打开单词本") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }

                Button("从剪切板添加") {
                    store.addFromClipboard(
                        mergeTags: (UserDefaults.standard.string(forKey: .defaultClipboardTags) ?? "")
                            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                        sourceHint: UserDefaults.standard.string(forKey: .defaultClipboardSource) ?? ""
                    )
                }

                Divider()

                Button("退出单词本") {
                    store.saveImmediately()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
            .frame(width: 200)
        } label: {
            let stats = store.stats()
            if stats.dueTodayCount > 0 {
                Label("\(stats.dueTodayCount)", systemImage: "text.book.closed")
            } else {
                Image(systemName: "text.book.closed")
            }
        }
    }
}
