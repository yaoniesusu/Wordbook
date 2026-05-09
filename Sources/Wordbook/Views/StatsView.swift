import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var store: WordbookStore
    @Binding var isPresented: Bool

    private var stats: WordbookStats { store.stats() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Space.large) {
                    metricGrid

                    GroupBox("近 7 天复习") {
                        weeklyChart
                            .frame(height: 180)
                    }

                    GroupBox("掌握分布") {
                        masteryChart
                            .frame(height: 160)
                    }

                    GroupBox("今日") {
                        VStack(alignment: .leading, spacing: 10) {
                            statRow("今日完成", value: "\(stats.reviewedTodayCount)")
                            statRow("今天到期", value: "\(stats.dueTodayCount)")
                            statRow("今日新增", value: "\(stats.newTodayCount)")
                            statRow("连续复习", value: "\(stats.studyStreakDays) 天")
                        }
                        .padding(4)
                    }

                    GroupBox("总体") {
                        VStack(alignment: .leading, spacing: 10) {
                            statRow("总词条", value: "\(stats.totalEntries)")
                            statRow("已掌握", value: "\(stats.masteredEntries)")
                            statRow("未掌握", value: "\(stats.unmasteredEntries)")
                            statRow("收藏", value: "\(stats.favoriteEntries)")
                            statRow("掌握率", value: stats.masteryRateText)
                        }
                        .padding(4)
                    }
                }
                .padding(AppTheme.Space.section)
            }
            .navigationTitle("学习统计")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { isPresented = false } } }
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Space.medium) {
            metricCard(title: "今日完成", value: "\(stats.reviewedTodayCount)", tint: .blue)
            metricCard(title: "今天到期", value: "\(stats.dueTodayCount)", tint: .orange)
            metricCard(title: "掌握率", value: stats.masteryRateText, tint: .green)
            metricCard(title: "连续复习", value: "\(stats.studyStreakDays)天", tint: .purple)
        }
    }

    private var weeklyChart: some View {
        let data = store.last7DaysReviewData()
        return Chart(data) { day in
            BarMark(x: .value("日期", day.label), y: .value("复习数", day.count))
                .foregroundStyle(Color.accentColor.gradient)
        }
        .chartXAxis { AxisMarks(values: .automatic) { _ in
            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
        }}
    }

    private var masteryChart: some View {
        let data: [(String, Int, Color)] = [
            ("已掌握", stats.masteredEntries, .green),
            ("学习中", stats.unmasteredEntries, .orange),
            ("未复习", stats.neverReviewedCount, .gray)
        ]
        return Chart(data, id: \.0) { item in
            BarMark(x: .value("分类", item.0), y: .value("数量", item.1))
                .foregroundStyle(item.2.gradient)
        }
        .chartLegend(.hidden)
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Space.cardPadding)
        .insetPill(cornerRadius: AppTheme.Radius.small, tint: tint, isActive: true)
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Text(value).font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
    }
}
