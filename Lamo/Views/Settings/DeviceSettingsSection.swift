import SwiftUI

/// Device benchmark section — start benchmark, show progress, display results.
/// Extracted from SettingsView for maintainability.
struct DeviceSettingsSection: View {
    @StateObject private var benchmark = DeviceBenchmark()

    var body: some View {
        Group {
            if benchmark.result != nil {
                BenchmarkResultView(result: benchmark.result!)
                    .navigationTitle("Benchmark Results")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await benchmark.runBenchmark() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .disabled(benchmark.isRunning)
                        }
                    }
            } else if benchmark.isRunning {
                progressView
            } else {
                startView
            }
        }
    }

    private var progressView: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    Text("Benchmark")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    ProgressView(value: benchmark.progress)
                        .tint(.white.opacity(0.5))

                    Text(progressLabel(benchmark.progress))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var startView: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    Text("Benchmark")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    Button {
                        Task { await benchmark.runBenchmark() }
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.system(.body, design: .monospaced))
                            Text("Start Benchmark")
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                    Text("Takes about 5–10 seconds. Tests CPU, GPU, memory and Neural Engine.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func progressLabel(_ progress: Double) -> String {
        switch progress {
        case 0..<0.15: return "Collecting device info…"
        case 0.15..<0.55: return "Testing CPU performance…"
        case 0.55..<0.85: return "Testing GPU performance…"
        case 0.85..<1.0: return "Analyzing results…"
        default: return "Done!"
        }
    }
}
