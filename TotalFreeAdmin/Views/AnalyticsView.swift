import SwiftUI

/// Lightweight analytics — the scanner pipeline stats (jsonb from admin_pipeline_stats).
/// Gated by analytics.view. Renders top-level numeric/scalar metrics.
struct AnalyticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var stats: [String: JSONValue] = [:]
    @State private var loading = false
    @State private var loaded = false

    private struct Metric: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private var metrics: [Metric] {
        stats.compactMap { key, value -> Metric? in
            let label = key.replacingOccurrences(of: "_", with: " ").capitalized
            switch value {
            case .int(let i): return Metric(label: label, value: String(i))
            case .double(let d): return Metric(label: label, value: d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d))
            case .string(let s): return Metric(label: label, value: s)
            case .bool(let b): return Metric(label: label, value: b ? "Yes" : "No")
            case .array(let a): return Metric(label: label, value: "\(a.count) items")
            default: return nil
            }
        }
        .sorted { $0.label < $1.label }
    }

    var body: some View {
        Group {
            if loading && stats.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if metrics.isEmpty {
                EmptyState(title: "No analytics yet", message: "Pipeline stats will appear here once there's activity.", systemImage: "chart.bar")
            } else {
                List {
                    Section("Scanner pipeline") {
                        ForEach(metrics) { m in
                            HStack {
                                Text(m.label)
                                Spacer()
                                Text(m.value).font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
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

    private func reload() async {
        loading = true
        defer { loading = false }
        if let r = await appState.load({ try await $0.fetchPipelineStats() }) { stats = r }
    }
}
