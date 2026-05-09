import SwiftUI

struct ManualEntrySheet: View {
    @EnvironmentObject private var store: WordbookStore
    @Binding var isPresented: Bool

    @State private var english = ""
    @State private var chinese = ""
    @State private var exampleSentence = ""
    @State private var tags = ""
    @State private var source = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case english
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("词条") {
                    TextField("英文", text: $english)
                        .focused($focusedField, equals: .english)
                    TextField("中文", text: $chinese)
                    TextField("例句 / 上下文", text: $exampleSentence, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
            Section("分类") {
                TextField("标签（逗号分隔）", text: $tags)
                tagSuggestions
                TextField("来源", text: $source)
            }
            }
            .formStyle(.grouped)
            .navigationTitle("手动新增")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .onAppear {
            focusedField = .english
        }
    }

    private var canSave: Bool {
        !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var tagSuggestions: some View {
        TagSuggestionBar(tagsField: tags, allTags: store.allTags) { tag in
            var parts = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if !parts.isEmpty { parts[parts.count - 1] = tag }
            tags = parts.joined(separator: ", ") + ", "
        }
    }

    private func save() {
        guard canSave else { return }
        store.addManualEntry(
            english: english,
            chinese: chinese,
            exampleSentence: exampleSentence,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            source: source.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isPresented = false
    }
}
