import Charts
import SwiftUI
import WafflezCore

/// Writing analytics: how much you've checked, what you've fixed, and your Effective Communication Score.
struct InsightsScreen: View {
    @ObservedObject var state = AppState.shared

    private var last30: [DayStats] {
        let cutoff = Insights.todayKey(Date().addingTimeInterval(-29 * 86400))
        return state.insights.days.filter { $0.day >= cutoff }.sorted { $0.day < $1.day }
    }

    private var ecs: Int {
        let samples = last30.filter { $0.scoreSamples > 0 }
        guard !samples.isEmpty else { return 0 }
        let total = samples.reduce(0) { $0 + $1.scoreTotal }
        let n = samples.reduce(0) { $0 + $1.scoreSamples }
        return Int((Double(total) / Double(n)).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Insights", subtitle: "Your last 30 days. Everything here is computed and stored on your Mac.")
                HStack(spacing: 12) {
                    tile("Effective Communication Score", ecs == 0 ? "—" : "\(ecs)", Theme.syrup)
                    tile("Words checked", "\(last30.reduce(0) { $0 + $1.wordsChecked })", Theme.indigo)
                    tile("Suggestions accepted", "\(last30.reduce(0) { $0 + $1.totalAccepted })", Theme.success)
                    tile("AI prompts", "\(state.insights.promptsThisMonth) this month", Theme.color(.delivery))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions accepted per day").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    if last30.isEmpty {
                        Text("Start writing — your activity will show up here.").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).frame(height: 160)
                    } else {
                        Chart {
                            ForEach(last30) { d in
                                ForEach(IssueCategory.allCases) { c in
                                    if let n = d.accepted[c], n > 0 {
                                        BarMark(x: .value("Day", shortDay(d.day)), y: .value("Accepted", n))
                                            .foregroundStyle(by: .value("Category", c.displayName))
                                    }
                                }
                            }
                        }
                        .chartForegroundStyleScale(domain: IssueCategory.allCases.map(\.displayName), range: IssueCategory.allCases.map { Theme.color($0) })
                        .frame(height: 200)
                    }
                }
                .card()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average score per day").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    let scored = last30.filter { $0.scoreSamples > 0 }
                    if scored.isEmpty {
                        Text("No scores yet.").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).frame(height: 120)
                    } else {
                        Chart(scored) { d in
                            LineMark(x: .value("Day", shortDay(d.day)), y: .value("Score", d.averageScore))
                                .foregroundStyle(Theme.syrup)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Day", shortDay(d.day)), y: .value("Score", d.averageScore))
                                .foregroundStyle(Theme.syrup)
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 160)
                    }
                }
                .card()
                VStack(alignment: .leading, spacing: 8) {
                    Text("What you fix most").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    let totals = Dictionary(uniqueKeysWithValues: IssueCategory.allCases.map { c in (c, last30.reduce(0) { $0 + ($1.accepted[c] ?? 0) }) })
                    let maxCount = max(1, totals.values.max() ?? 1)
                    ForEach(IssueCategory.allCases) { c in
                        let n = totals[c] ?? 0
                        HStack(spacing: 10) {
                            CategoryDot(category: c)
                            Text(c.displayName).frame(width: 110, alignment: .leading).foregroundStyle(Theme.text)
                            GeometryReader { g in
                                Capsule().fill(Theme.raised).overlay(alignment: .leading) {
                                    Capsule().fill(Theme.color(c)).frame(width: g.size.width * CGFloat(n) / CGFloat(maxCount))
                                }
                            }
                            .frame(height: 8)
                            Text("\(n)").frame(width: 40, alignment: .trailing).foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 12.5))
                    }
                }
                .card()
            }
            .padding(.horizontal, 28).padding(.top, 38).padding(.bottom, 28)
        }
    }

    private func tile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func shortDay(_ key: String) -> String { String(key.suffix(5)) }
}
