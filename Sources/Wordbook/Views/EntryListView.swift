import SwiftUI

struct EntryListView: View {
    @EnvironmentObject private var store: WordbookStore
    @Binding var selection: UUID?
    var filter: EntryFilter
    var searchText: String
    let entries: [VocabularyEntry]
    @State private var pendingDeletion: VocabularyEntry?
    @State private var editMode = false
    @State private var selectedIDs = Set<UUID>()

    var body: some View {
        Group {
            if editMode {
                batchToolbar
            }
            if entries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        row(entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button { toggleFavorite(entry) } label: {
                                    Label(entry.isFavorite ? "取消收藏" : "收藏", systemImage: entry.isFavorite ? "star.slash" : "star")
                                }
                                Button { toggleMastered(entry) } label: {
                                    Label(entry.isMastered ? "标记为学习中" : "标记为已掌握", systemImage: entry.isMastered ? "book" : "checkmark.seal")
                                }
                                Divider()
                                Button(role: .destructive) { pendingDeletion = entry } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .confirmationDialog("删除词条？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { entry in
            Button("删除 \(entry.english)", role: .destructive) {
                store.delete(ids: [entry.id])
                if selection == entry.id { selection = nil }
                pendingDeletion = nil
            }
        } message: { entry in
            Text("这会从单词本中移除「\(entry.english)」。")
        }
    }

    private var batchToolbar: some View {
        HStack(spacing: AppTheme.Space.small) {
            Button { editMode = false; selectedIDs = [] } label: {
                Label("完成", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            Spacer()
            Text("已选 \(selectedIDs.count) 条")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button { batchToggleMastered(true) } label: {
                Label("掌握", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIDs.isEmpty)
            Button { batchToggleMastered(false) } label: {
                Label("学习中", systemImage: "book")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIDs.isEmpty)
            Button(role: .destructive) { batchDelete() } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, AppTheme.Space.large)
        .padding(.vertical, AppTheme.Space.small)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(AppTheme.Stroke.subtle))
                .frame(height: AppTheme.Stroke.hairline)
        }
    }

    private func row(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: AppTheme.Space.small) {
            if editMode {
                Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedIDs.contains(entry.id) ? Color.accentColor : .secondary)
                    .onTapGesture { toggleSelection(entry.id) }
                    .accessibilityLabel(selectedIDs.contains(entry.id) ? "已选中" : "未选中")
            }
            Circle()
                .fill(familiarityColor(for: entry))
                .frame(width: AppTheme.Size.statusDot, height: AppTheme.Size.statusDot)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: AppTheme.Space.xSmall) {
                    Text(entry.english)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if entry.isMastered {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if !entry.chinese.isEmpty {
                    Text(entry.chinese)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let nextReviewAt = entry.nextReviewAt, !entry.isMastered {
                    Text(nextReviewAt, format: .dateTime.month(.defaultDigits).day().hour().minute())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Size.sidebarRowHeight, alignment: .center)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.english), \(entry.chinese)")
    }

    private var emptyState: some View {
        VStack(spacing: AppTheme.Space.small) {
            Image(systemName: "text.book.closed").font(.title2).foregroundStyle(.tertiary)
            Text(emptyTitle).font(.body.weight(.semibold))
            Text(emptyMessage).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, AppTheme.Space.section)
        }
        .accessibilityLabel("\(emptyTitle), \(emptyMessage)")
    }

    private var emptyTitle: String {
        if hasSearch { return "没有匹配结果" }
        switch filter {
        case .all: return "暂无词条"
        case .favorites: return "还没有收藏"
        case .unmastered: return "没有学习中的词条"
        case .mastered: return "还没有已掌握词条"
        }
    }

    private var emptyMessage: String {
        if hasSearch { return "换个关键词试试" }
        switch filter {
        case .all: return "复制英文或手动新增一个词条"
        case .favorites: return "右键词条可收藏"
        case .unmastered: return "未掌握词条会在这里继续参与复习"
        case .mastered: return "复习到很熟后会自动出现在这里"
        }
    }

    private var hasSearch: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func batchToggleMastered(_ mastered: Bool) {
        store.setMastered(mastered, ids: selectedIDs)
        selectedIDs = []
        editMode = false
    }

    private func batchDelete() {
        store.delete(ids: selectedIDs)
        if let sel = selection, selectedIDs.contains(sel) { selection = nil }
        selectedIDs = []
        editMode = false
    }

    private func toggleFavorite(_ entry: VocabularyEntry) {
        var updated = entry; updated.isFavorite.toggle(); store.update(updated)
    }

    private func toggleMastered(_ entry: VocabularyEntry) {
        var updated = entry; updated.isMastered.toggle(); store.update(updated)
    }

    private func familiarityColor(for entry: VocabularyEntry) -> Color {
        if entry.isMastered { return .green }
        switch entry.reviewCount {
        case 0:  return Color(red: 0.65, green: 0.65, blue: 0.65)
        case 1:  return Color(red: 0.95, green: 0.55, blue: 0.25)
        case 2:  return Color(red: 0.90, green: 0.60, blue: 0.20)
        case 3:  return Color(red: 0.85, green: 0.70, blue: 0.15)
        case 4:  return Color(red: 0.65, green: 0.75, blue: 0.15)
        case 5:  return Color(red: 0.40, green: 0.70, blue: 0.40)
        case 6:  return Color(red: 0.25, green: 0.65, blue: 0.50)
        case 7:  return Color(red: 0.20, green: 0.60, blue: 0.55)
        case 8:  return Color(red: 0.15, green: 0.55, blue: 0.60)
        default: return Color(red: 0.10, green: 0.50, blue: 0.55)
        }
    }
}
