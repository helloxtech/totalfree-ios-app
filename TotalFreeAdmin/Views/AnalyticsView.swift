import SwiftUI
import Charts

/// Website statistics dashboard (item 7): traffic & growth over the last 30 days
/// plus what's being shared, from admin_daily_impact_report. Gated by analytics.view.
struct AnalyticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var report: ImpactReport?
    @State private var loading = false
    @State private var loaded = false

    private var summary: ImpactSummary? { report?.summary }
    private var series: [ImpactDay] { report?.series ?? [] }

    private struct SeriesPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Int
        let metric: String
    }

    private func trafficPoints() -> [SeriesPoint] {
        series.flatMap { d -> [SeriesPoint] in
            let day = Self.parse(d.date)
            return [
                SeriesPoint(date: day, value: d.pageViews ?? 0, metric: "Page views"),
                SeriesPoint(date: day, value: d.activeUsers ?? 0, metric: "Active users"),
                SeriesPoint(date: day, value: d.newUsers ?? 0, metric: "New neighbours"),
            ]
        }
    }
    private func activityPoints() -> [SeriesPoint] {
        series.flatMap { d -> [SeriesPoint] in
            let day = Self.parse(d.date)
            return [
                SeriesPoint(date: day, value: d.posts ?? 0, metric: "New posts"),
                SeriesPoint(date: day, value: d.requests ?? 0, metric: "Requests"),
            ]
        }
    }

    var body: some View {
        Group {
            if loading && report == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if report == nil {
                EmptyState(title: "No analytics yet", message: "Website statistics appear here once there's activity.", systemImage: "chart.bar")
            } else {
                List {
                    Section("Today") { kpiGrid }

                    Section("Website traffic · last 30 days") {
                        if series.isEmpty {
                            Text("No traffic recorded yet.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Chart(trafficPoints()) { p in
                                LineMark(x: .value("Day", p.date), y: .value("Count", p.value))
                                    .foregroundStyle(by: .value("Metric", p.metric))
                                    .interpolationMethod(.catmullRom)
                            }
                            .chartLegend(position: .bottom)
                            .frame(height: 200)
                            .padding(.vertical, 6)
                        }
                    }

                    Section("Community activity · last 30 days") {
                        if series.isEmpty {
                            Text("No activity recorded yet.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Chart(activityPoints()) { p in
                                BarMark(x: .value("Day", p.date, unit: .day), y: .value("Count", p.value))
                                    .foregroundStyle(by: .value("Metric", p.metric))
                                    .position(by: .value("Metric", p.metric))
                            }
                            .chartLegend(position: .bottom)
                            .frame(height: 180)
                            .padding(.vertical, 6)
                        }
                    }

                    if let mix = report?.categoryMix, !mix.isEmpty {
                        Section("Active listings by category") {
                            Chart(mix) { c in
                                BarMark(x: .value("Count", c.count), y: .value("Category", humanize(c.category)))
                                    .foregroundStyle(Theme.accent)
                            }
                            .frame(height: CGFloat(max(140, mix.count * 30)))
                            .padding(.vertical, 6)
                        }
                    }

                    if let events = report?.trafficEvents, !events.isEmpty {
                        Section("Top events today") {
                            ForEach(events.prefix(8)) { e in
                                HStack {
                                    Text(humanize(e.event))
                                    Spacer()
                                    Text("\(e.count)").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { if !loaded { await reload(); loaded = true } }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            kpi("Active users", summary?.activeUsers)
            kpi("Page views", summary?.pageViews)
            kpi("New neighbours", summary?.newUsers)
            kpi("New posts", summary?.postsSubmitted)
            kpi("Requests", summary?.requestsCreated)
            kpi("Messages", summary?.messagesSent)
        }
        .padding(.vertical, 6)
    }

    private func kpi(_ label: String, _ value: Int?) -> some View {
        VStack(spacing: 3) {
            Text("\(value ?? 0)").font(.title3.bold()).foregroundStyle(Theme.accent)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func humanize(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchImpactReport() }) { report = r }
    }

    private static func parse(_ ymd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: ymd) ?? Date()
    }
}
