import SwiftUI

import AppKit

/// 选择题复习：看英文，从 4 个中文选项中选出正确翻译。
struct DailyReviewView: View {
    @EnvironmentObject private var store: WordbookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var batch: [VocabularyEntry] = []
    @State private var index = 0
    @State private var completedCount = 0
    @State private var lastFeedback: String?
    @State private var outcomeCounts: [ReviewOutcome: Int] = [:]
    @State private var isAdvancing = false
    @AppStorage("reviewBatchSize") private var reviewBatchSize = 5
    @AppStorage("shuffleReview") private var shuffleReview = false
    @State private var suppressInitialAnimation = true
    @ScaledMetric private var reviewWordSize: CGFloat = 32

    // 选择题状态
    @State private var options: [String] = []
    @State private var selectedOptionIndex: Int? = nil
    @State private var answerCorrect: Bool? = nil
    @State private var autoAdvanceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: AppTheme.Space.large) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("每日复习")
                        .font(.title3.weight(.semibold))
                    Text(progressText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Picker("批次", selection: $reviewBatchSize) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("20").tag(20)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                    Toggle(isOn: $shuffleReview) {
                        Image(systemName: "shuffle")
                    }
                    .toggleStyle(.button)
                    .help("随机顺序")
                }
                Button("关闭") { closeReview() }
            }

            if batch.isEmpty {
                completionView
            } else {
                quizCard(batch[index])
            }
        }
        .padding(AppTheme.Space.page)
        .frame(minWidth: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(keyboardCapture)
        .onAppear { loadBatch() }
        .onChange(of: reviewBatchSize) { _ in loadBatch() }
        .animation(suppressInitialAnimation ? nil : .easeInOut(duration: 0.16), value: isAdvancing)
        .animation(suppressInitialAnimation ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: index)
    }

    // MARK: - Quiz Card

    private func quizCard(_ current: VocabularyEntry) -> some View {
        VStack(spacing: AppTheme.Space.large) {
            // 单词区
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(current.english)
                        .font(.system(size: reviewWordSize, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                    Button {
                        SpeechService.speak(current.english)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help("朗读单词")
                }
                .frame(maxWidth: .infinity)

                if !current.exampleSentence.isEmpty {
                    Text(current.exampleSentence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.horizontal, AppTheme.Space.section)
            .padding(.vertical, AppTheme.Space.xLarge)
            .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 3)
            .offset(x: isAdvancing ? -26 : 0)
            .opacity(isAdvancing ? 0.45 : 1)

            // 选项区
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, chinese in
                    optionButton(chinese, index: idx)
                }
            }

            // 导航
            HStack {
                Button("上一条") { step(-1) }.disabled(index == 0)
                Spacer()
                Text("\(index + 1) / \(batch.count)  ·  已完成 \(completedCount)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下一条") { step(1) }.disabled(index >= batch.count - 1)
            }
            .padding(.horizontal)

            if let lastFeedback {
                Text(lastFeedback)
                    .font(.callout)
                    .foregroundStyle(answerCorrect == true ? .green : .red)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if PlatformFeatures.supportsKeyboardReviewShortcuts {
                Text("快捷键：1/2/3/4 选择答案，Esc 关闭")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Option Button

    private func optionButton(_ chinese: String, index optIndex: Int) -> some View {
        Button {
            selectOption(optIndex)
        } label: {
            HStack(spacing: 10) {
                Text(keyLabel(for: optIndex))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
                Text(chinese)
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(optionBackground(for: optIndex))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .strokeBorder(optionBorderColor(for: optIndex), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(answerCorrect != nil)
    }

    private func keyLabel(for index: Int) -> String {
        ["1", "2", "3", "4"][safe: index] ?? "\(index + 1)"
    }

    private func optionBackground(for optIndex: Int) -> Color {
        guard let selected = selectedOptionIndex else {
            return Color.primary.opacity(0.04)
        }
        let correctChinese = batch[safe: index]?.chinese ?? ""
        let isThisCorrect = options[safe: optIndex] == correctChinese

        if optIndex == selected && isThisCorrect {
            return Color.green.opacity(0.18)
        } else if optIndex == selected && !isThisCorrect {
            return Color.red.opacity(0.18)
        } else if selectedOptionIndex != nil && isThisCorrect {
            return Color.green.opacity(0.18)
        }
        return Color.primary.opacity(0.04)
    }

    private func optionBorderColor(for optIndex: Int) -> Color {
        guard let selected = selectedOptionIndex else {
            return Color.primary.opacity(0.08)
        }
        let correctChinese = batch[safe: index]?.chinese ?? ""
        let isThisCorrect = options[safe: optIndex] == correctChinese

        if optIndex == selected && isThisCorrect {
            return Color.green.opacity(0.5)
        } else if optIndex == selected && !isThisCorrect {
            return Color.red.opacity(0.5)
        } else if selectedOptionIndex != nil && isThisCorrect {
            return Color.green.opacity(0.5)
        }
        return Color.primary.opacity(0.08)
    }

    // MARK: - Actions

    private func generateOptions(for entry: VocabularyEntry) -> [String] {
        let correctChinese = entry.chinese.isEmpty ? "（无中文）" : entry.chinese

        let otherChinese = store.entries
            .filter { $0.id != entry.id && !$0.chinese.isEmpty }
            .map { $0.chinese }

        let uniqueWrong = Array(Set(otherChinese)).shuffled().prefix(3)

        var allOptions = [correctChinese] + uniqueWrong
        allOptions.shuffle()
        return allOptions
    }

    private func selectOption(_ optIndex: Int) {
        guard answerCorrect == nil, !isAdvancing, optIndex < options.count else { return }
        autoAdvanceTask?.cancel()

        guard let current = batch[safe: index] else { return }
        let correctChinese = current.chinese.isEmpty ? "（无中文）" : current.chinese
        let isCorrect = options[optIndex] == correctChinese

        selectedOptionIndex = optIndex
        answerCorrect = isCorrect

        let outcome: ReviewOutcome = isCorrect ? .remembered : .forgot
        store.review(current, outcome: outcome)
        outcomeCounts[outcome, default: 0] += 1

        lastFeedback = isCorrect
            ? "正确！"
            : "错误！正确答案：\(correctChinese)"

        completedCount += 1

        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { advanceToNext() }
        }
    }

    private func advanceToNext() {
        withAnimation { isAdvancing = true }

        selectedOptionIndex = nil
        answerCorrect = nil
        options = []

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation {
                batch.removeAll { $0.id == batch[safe: index]?.id }
                if batch.isEmpty {
                    let next = store.dueReviewBatch(count: reviewBatchSize)
                    if !next.isEmpty {
                        batch = shuffleReview ? next.shuffled() : next
                        index = 0
                    }
                } else {
                    index = min(index, batch.count - 1)
                }
                isAdvancing = false
                if !batch.isEmpty, let current = batch[safe: index] {
                    options = generateOptions(for: current)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            lastFeedback = nil
        }
    }

    private func step(_ delta: Int) {
        autoAdvanceTask?.cancel()
        withAnimation {
            index = min(max(0, index + delta), max(0, batch.count - 1))
            answerCorrect = nil
            selectedOptionIndex = nil
            lastFeedback = nil
            if let current = batch[safe: index] {
                options = generateOptions(for: current)
            }
        }
    }

    private func closeReview() {
        isPresented = false
        dismiss()
    }

    private func loadBatch() {
        batch = store.dueReviewBatch(count: reviewBatchSize)
        if shuffleReview { batch.shuffle() }
        index = 0
        completedCount = 0
        outcomeCounts = [:]
        lastFeedback = nil
        isAdvancing = false
        answerCorrect = nil
        selectedOptionIndex = nil
        options = []
        if let first = batch.first {
            options = generateOptions(for: first)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            suppressInitialAnimation = false
        }
    }

    // MARK: - Completion

    private var completionView: some View {
        let summary = store.reviewSessionSummary(outcomes: outcomeCounts)
        return VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46))
                .foregroundStyle(.green)
            Text(completedCount == 0 ? "没有可复习的条目" : "今天这组完成了")
                .font(.title2.weight(.semibold))
            Text(completedCount == 0 ? "全部已掌握或还没有到期词条。" : "刚刚复习了 \(completedCount) 条，下一轮会按你的反馈安排。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if completedCount > 0 {
                HStack(spacing: 10) {
                    summaryTile("完成", "\(summary.completedCount)", color: .blue)
                    summaryTile("正确", "\(summary.rememberedCount)", color: .green)
                    summaryTile("错误", "\(summary.forgotCount)", color: .red)
                    summaryTile("今日剩余", "\(summary.upcomingDueCount)", color: .orange)
                }
                .frame(maxWidth: 430)
            }
            Button("关闭") { closeReview() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Space.page)
        .surfaceCard(cornerRadius: AppTheme.Radius.prominent, material: .regularMaterial, shadowOpacity: 0.055, shadowRadius: 14, shadowY: 6)
    }

    private var progressText: String {
        if batch.isEmpty {
            return completedCount == 0 ? "今天暂时没有到期任务。" : "本组已完成。"
        }
        return "看英文，选择正确的中文翻译。"
    }

    private func summaryTile(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .insetPill(cornerRadius: AppTheme.Radius.medium, tint: color, isActive: true)
    }

    // MARK: - Keyboard

    @ViewBuilder
    private var keyboardCapture: some View {
        KeyCaptureView { handleKey($0) }
    }

    private func handleKey(_ event: KeyCaptureView.KeyEvent) {
        switch event {
        case .space:
            break
        case .escape:
            isPresented = false
        case .option(let idx):
            guard !batch.isEmpty, answerCorrect == nil, idx < options.count else { return }
            selectOption(idx)
        }
    }
}

// MARK: - Key Capture

private struct KeyCaptureView: NSViewRepresentable {
    enum KeyEvent {
        case space
        case escape
        case option(Int)
    }

    let onKey: (KeyEvent) -> Void

    func makeNSView(context: Context) -> KeyCatcher {
        let view = KeyCatcher()
        view.onKey = onKey
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCatcher, context: Context) {
        nsView.onKey = onKey
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyCatcher: NSView {
        var onKey: ((KeyEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 49: onKey?(.space)
            case 53: onKey?(.escape)
            case 18: onKey?(.option(0))
            case 19: onKey?(.option(1))
            case 20: onKey?(.option(2))
            case 21: onKey?(.option(3))
            default: super.keyDown(with: event)
            }
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
