import SwiftUI

import AppKit

private enum ReviewMode: String, CaseIterable {
    case normal, reverse, spelling, cloze
    var title: String {
        switch self {
        case .normal: return "正常"
        case .reverse: return "反向"
        case .spelling: return "拼写"
        case .cloze: return "挖空"
        }
    }
    var systemImage: String {
        switch self {
        case .normal: return "textformat"
        case .reverse: return "arrow.left.arrow.right"
        case .spelling: return "pencil"
        case .cloze: return "rectangle.fill.badge.person.crop"
        }
    }
    var helpText: String {
        switch self {
        case .normal: return "看英文，想中文"
        case .reverse: return "反向：看中文想英文"
        case .spelling: return "拼写模式：看中文，打出英文"
        case .cloze: return "挖空模式：从例句填空回忆单词"
        }
    }
    var progressHint: String {
        switch self {
        case .normal: return "看英文，翻答案，再选择记忆程度。"
        case .reverse: return "看中文，回忆英文，再选择记忆程度。"
        case .spelling: return "看中文，拼写英文，再评分记忆程度。"
        case .cloze: return "根据上下文填空，再评分记忆程度。"
        }
    }
}

/// 从未掌握池中取最多 5 条，支持模糊显示与四档复习反馈。
struct DailyReviewView: View {
    @EnvironmentObject private var store: WordbookStore
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    @State private var batch: [VocabularyEntry] = []
    @State private var index = 0
    @State private var reveal = false
    @State private var completedCount = 0
    @State private var lastFeedback: String?
    @State private var outcomeCounts: [ReviewOutcome: Int] = [:]
    @State private var isAdvancing = false
    @AppStorage("fuzzyRecallEnabled") private var fuzzyRecallEnabled = false
    @AppStorage("reviewBatchSize") private var reviewBatchSize = 5
    @AppStorage("shuffleReview") private var shuffleReview = false
    @AppStorage("reverseReview") private var reverseReview = false
    @AppStorage("spellingMode") private var spellingMode = false
    @AppStorage("clozeMode") private var clozeMode = false
    @State private var spellingInput = ""
    @State private var spellingResult: Bool? = nil
    @FocusState private var spellingFocused: Bool
    @State private var suppressInitialAnimation = true

    private var reviewMode: ReviewMode {
        if clozeMode { return .cloze }
        if spellingMode { return .spelling }
        if reverseReview { return .reverse }
        return .normal
    }

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
                    .frame(width: 120)
                    Picker("模式", selection: Binding<ReviewMode>(
                        get: { reviewMode },
                        set: { newMode in
                            reverseReview = false
                            spellingMode = false
                            clozeMode = false
                            switch newMode {
                            case .reverse: reverseReview = true
                            case .spelling: spellingMode = true
                            case .cloze: clozeMode = true
                            case .normal: break
                            }
                        }
                    )) {
                        ForEach(ReviewMode.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                    .help(reviewMode.helpText)
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
                reviewCard(batch[index])
            }
        }
        .padding(.horizontal, AppTheme.Space.page)
        .padding(.bottom, AppTheme.Space.page)
        .padding(.top, AppTheme.Space.page + 44)
        .frame(minWidth: 620, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(keyboardCapture)
        .onAppear {
            loadBatch()
        }
        .onChange(of: reviewBatchSize) { _ in
            loadBatch()
        }
        .animation(suppressInitialAnimation ? nil : .easeInOut(duration: 0.18), value: reveal)
        .animation(suppressInitialAnimation ? nil : .easeInOut(duration: 0.16), value: isAdvancing)
        .animation(suppressInitialAnimation ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: index)
    }

    private func reviewCard(_ current: VocabularyEntry) -> some View {
        VStack(spacing: AppTheme.Space.large) {
            VStack(spacing: AppTheme.Space.large) {
            if reviewMode == .cloze {
                    let clozeSentence = current.exampleSentence.isEmpty
                        ? current.english
                        : current.exampleSentence.replacingOccurrences(of: current.english, with: "_____", options: .caseInsensitive)
                    VStack(spacing: 12) {
                        Text("根据上下文和释义填空")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(clozeSentence)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)
                            .padding(.vertical, 8)
                        Text(current.chinese.isEmpty ? "（无中文）" : current.chinese)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                        Button { SpeechService.speak(clozeSentence) } label: {
                            Label("朗读例句", systemImage: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)

                        HStack(spacing: 8) {
                            TextField("输入缺失的单词…", text: $spellingInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .focused($spellingFocused)
                                .onSubmit { checkCloze(current) }
                            Button("检查") { checkCloze(current) }
                                .buttonStyle(.borderedProminent)
                        }

                        if let result = spellingResult {
                            HStack(spacing: 6) {
                                Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result ? .green : .red)
                                Text(result ? "正确！" : "缺失词：\(current.english)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if reveal || spellingResult == true {
                            HStack(spacing: 12) {
                                scoreButton("1 没记住", systemImage: "xmark.circle", tint: .red, outcome: .forgot)
                                scoreButton("2 模糊", systemImage: "questionmark.circle", tint: .orange, outcome: .hard)
                                scoreButton("3 记住了", systemImage: "checkmark.circle", tint: .blue, outcome: .remembered)
                                scoreButton("4 很熟", systemImage: "sparkles", tint: .green, outcome: .easy)
                            }
                            .padding(8)
                            .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
                        }
                    }
            } else if reviewMode == .spelling {
                    Text(current.chinese.isEmpty ? "（无中文）" : current.chinese)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)
                    Button { SpeechService.speak(current.english) } label: {
                        Label("播放发音", systemImage: "speaker.wave.2")
                    }
                    .buttonStyle(.borderless)

                    HStack(spacing: 8) {
                        TextField("输入英文…", text: $spellingInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                            .focused($spellingFocused)
                            .onSubmit { checkSpelling(current) }
                        Button("检查") { checkSpelling(current) }
                            .buttonStyle(.borderedProminent)
                    }

                    if let result = spellingResult {
                        HStack(spacing: 6) {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                            Text(result ? "正确！" : "正确拼写：\(current.english)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if reveal || spellingResult == true {
                        HStack(spacing: 12) {
                            scoreButton("1 没记住", systemImage: "xmark.circle", tint: .red, outcome: .forgot)
                            scoreButton("2 模糊", systemImage: "questionmark.circle", tint: .orange, outcome: .hard)
                            scoreButton("3 记住了", systemImage: "checkmark.circle", tint: .blue, outcome: .remembered)
                            scoreButton("4 很熟", systemImage: "sparkles", tint: .green, outcome: .easy)
                        }
                        .padding(8)
                        .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial)
                    }
            } else if reviewMode == .reverse {
                    VStack(spacing: 14) {
                        Text(current.chinese.isEmpty ? "（无中文）" : current.chinese)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)

                        if fuzzyRecallEnabled && !reveal {
                            Button { revealAnswer() } label: {
                                Label("显示答案", systemImage: "eye")
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(current.english)
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
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
                        }
                    }
                    .frame(maxWidth: .infinity)
            } else {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(current.english)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
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

                    if fuzzyRecallEnabled && !reveal {
                        Button { revealAnswer() } label: {
                            Label("显示答案", systemImage: "eye")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(current.chinese.isEmpty ? "（无中文）" : current.chinese)
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(7)
                            .lineLimit(3)
                            .minimumScaleFactor(0.74)
                    }
                }

                if reveal, !current.exampleSentence.isEmpty {
                    Text(current.exampleSentence)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }

            }
            .frame(maxWidth: .infinity, minHeight: 238)
            .padding(.horizontal, AppTheme.Space.section)
            .padding(.vertical, AppTheme.Space.xLarge)
            .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial, shadowOpacity: 0.025, shadowRadius: 8, shadowY: 3)
            .offset(x: isAdvancing ? -26 : 0)
            .opacity(isAdvancing ? 0.45 : 1)

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
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        if reviewMode == .normal || reviewMode == .reverse {
                HStack(spacing: AppTheme.Space.small) {
                    scoreButton("1 没记住", systemImage: "xmark.circle", tint: .red, outcome: .forgot)
                    scoreButton("2 模糊", systemImage: "questionmark.circle", tint: .orange, outcome: .hard)
                    scoreButton("3 记住了", systemImage: "checkmark.circle", tint: .blue, outcome: .remembered)
                    scoreButton("4 很熟", systemImage: "sparkles", tint: .green, outcome: .easy)
                }
                .padding(AppTheme.Space.small)
                .surfaceCard(cornerRadius: AppTheme.Radius.panel, material: .thinMaterial, strokeOpacity: AppTheme.Stroke.subtle, shadowOpacity: 0.012, shadowRadius: 4, shadowY: 1)
                .disabled((fuzzyRecallEnabled && !reveal) || isAdvancing)
            }

            if PlatformFeatures.supportsKeyboardReviewShortcuts {
                Text("快捷键：Space 翻答案，1/2/3/4 评分，Esc 关闭")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var keyboardCapture: some View {
        KeyCaptureView { handleKey($0) }
    }

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
                    summaryTile("忘记", "\(summary.forgotCount)", color: .red)
                    summaryTile("简单", "\(summary.easyCount)", color: .green)
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
        return reviewMode.progressHint
    }

    private func scoreButton(_ title: String, systemImage: String, tint: Color, outcome: ReviewOutcome) -> some View {
        Button {
            record(batch[index], outcome: outcome)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background {
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .strokeBorder(tint.opacity(0.16), lineWidth: AppTheme.Stroke.hairline)
                }
        }
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

    private func step(_ delta: Int) {
        withAnimation {
            index = min(max(0, index + delta), max(0, batch.count - 1))
            reveal = !fuzzyRecallEnabled
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
        reveal = !fuzzyRecallEnabled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            suppressInitialAnimation = false
        }
    }

    private func record(_ entry: VocabularyEntry, outcome: ReviewOutcome) {
        guard !isAdvancing else { return }
        store.review(entry, outcome: outcome)
        outcomeCounts[outcome, default: 0] += 1
        let feedback = feedbackText(for: outcome)
        lastFeedback = feedback
        completedCount += 1

        withAnimation {
            isAdvancing = true
        }

        // 重置拼写状态
        spellingInput = ""
        spellingResult = nil
        reveal = !fuzzyRecallEnabled

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation {
                batch.removeAll { $0.id == entry.id }
                if batch.isEmpty {
                    let next = store.dueReviewBatch(count: reviewBatchSize)
                    if next.isEmpty {
                        // 确实没词了
                    } else {
                        batch = shuffleReview ? next.shuffled() : next
                        index = 0
                        reveal = !fuzzyRecallEnabled
                    }
                } else {
                    index = min(index, batch.count - 1)
                    reveal = !fuzzyRecallEnabled
                }
                isAdvancing = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if lastFeedback == feedback { lastFeedback = nil }
        }
    }

    private func checkCloze(_ entry: VocabularyEntry) {
        let input = spellingInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = entry.english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        spellingResult = input == correct
        if spellingResult == true {
            reveal = true
            spellingInput = ""
        }
    }

    private func checkSpelling(_ entry: VocabularyEntry) {
        let input = spellingInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = entry.english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        spellingResult = input == correct
        if spellingResult == true {
            reveal = true
            spellingInput = ""
        }
    }

    private func revealAnswer() {
        withAnimation(.easeOut(duration: 0.18)) {
            reveal = true
        }
    }

    private func handleKey(_ event: KeyCaptureView.KeyEvent) {
        switch event {
        case .space:
            revealAnswer()
        case .escape:
            isPresented = false
        case .score(let outcome):
            guard !batch.isEmpty else { return }
            if (reviewMode == .spelling || reviewMode == .cloze), spellingFocused { return }
            if fuzzyRecallEnabled && !reveal {
                withAnimation(.easeOut(duration: 0.18)) { reveal = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    guard !batch.isEmpty else { return }
                    record(batch[index], outcome: outcome)
                }
            } else {
                record(batch[index], outcome: outcome)
            }
        }
    }

    private func feedbackText(for outcome: ReviewOutcome) -> String {
        switch outcome {
        case .forgot:
            return "已记录：稍后再碰一次，别急。"
        case .hard:
            return "已记录：明天再巩固。"
        case .remembered:
            return "已记录：间隔推进一档。"
        case .easy:
            return "已记录：很稳，间隔推进更远。"
        }
    }

}

private struct KeyCaptureView: NSViewRepresentable {
    enum KeyEvent {
        case space
        case escape
        case score(ReviewOutcome)
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
            case 49:
                onKey?(.space)
            case 53:
                onKey?(.escape)
            case 18:
                onKey?(.score(.forgot))
            case 19:
                onKey?(.score(.hard))
            case 20:
                onKey?(.score(.remembered))
            case 21:
                onKey?(.score(.easy))
            default:
                super.keyDown(with: event)
            }
        }
    }
}
