import SwiftUI

struct BenchmarkResultView: View {
    let result: DeviceBenchmark.BenchmarkResult
    @State private var showContent = false
    @State private var scoreAnimated: Double = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                scoreGauge
                hardwareSection
                performanceSection
                modelCompatibility
                if !result.recommendations.isEmpty {
                    recommendationsSection
                }
                timingSection
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .background(LamoTheme.Colors.background)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                showContent = true
            }
            withAnimation(.easeOut(duration: 1.2).delay(0.4)) {
                scoreAnimated = result.scoreNormalized
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Device icon with tier ring
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        tierColor.opacity(0.2),
                        lineWidth: 6
                    )
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: showContent ? result.scoreNormalized : 0)
                    .stroke(
                        tierColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2).delay(0.4), value: showContent)

                // Inner icon
                ZStack {
                    Circle()
                        .fill(tierColor.opacity(0.15))
                        .frame(width: 76, height: 76)
                    Image(systemName: result.aiTierIcon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(tierColor)
                }
            }

            // Device name + chip
            VStack(spacing: 4) {
                Text(result.deviceName)
                    .font(.title2.weight(.semibold))
                Text(result.chipName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Tier badge
            HStack(spacing: 6) {
                Image(systemName: result.aiTierIcon)
                    .font(.caption)
                Text(result.aiTierLabel)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(tierColor.opacity(0.15))
            .foregroundStyle(tierColor)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Score Gauge

    private var scoreGauge: some View {
        VStack(spacing: 12) {
            // Large score number
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", result.combinedScore * (showContent ? 1 : 0)))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(tierColor)
                Text("GFLOPS")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 1.0).delay(0.5), value: showContent)

            Text("AI Performance Score")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tierColor, tierColor.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * scoreAnimated, height: 8)
                        .animation(.easeOut(duration: 1.2).delay(0.4), value: scoreAnimated)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 20)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Hardware

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hardware", systemImage: "internaldrive")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                hardwareCard(icon: "memorychip", title: "Memory", value: String(format: "%.1f GB", result.ramGB))
                hardwareCard(icon: "gpu", title: "GPU Cores", value: result.hasGPU ? "\(result.gpuCoreCount)" : "—")
                hardwareCard(icon: "internaldrive", title: "Free", value: String(format: "%.1f GB", result.storageFreeGB))
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func hardwareCard(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(LamoTheme.Colors.accent)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Performance Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            // CPU
            perfRow(
                icon: "cpu.fill",
                title: "CPU",
                score: result.cpuScore,
                normalized: result.cpuNormalized,
                time: result.cpuTime,
                maxScore: 3.0
            )

            // GPU
            if result.hasGPU {
                perfRow(
                    icon: "gpu",
                    title: "GPU",
                    score: result.gpuScore,
                    normalized: result.gpuNormalized,
                    time: result.gpuTime,
                    maxScore: 6.0
                )
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func perfRow(icon: String, title: String, score: Double, normalized: Double, time: Double, maxScore: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(scoreColor(score))
                    Text(title)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Text(String(format: "%.2f GFLOPS", score))
                    .font(.subheadline.monospacedDigit())
                scoreBadge(score)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 6)
                    Capsule()
                        .fill(scoreColor(score))
                        .frame(width: geo.size.width * normalized, height: 6)
                        .animation(.easeOut(duration: 1.0).delay(0.6), value: showContent)
                }
            }
            .frame(height: 6)

            Text(String(format: "Completed in %.2fs", time))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func scoreBadge(_ gflops: Double) -> some View {
        Text(scoreLabel(gflops))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(scoreColor(gflops).opacity(0.15))
            .foregroundStyle(scoreColor(gflops))
            .clipShape(Capsule())
    }

    // MARK: - Model Compatibility

    private var modelCompatibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model Compatibility", systemImage: "cpu.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(result.modelCompatibility) { compat in
                HStack(spacing: 10) {
                    Image(systemName: compat.icon)
                        .foregroundStyle(Color(compat.status.color == "green" ? .systemGreen : .systemOrange))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(compat.name)
                            .font(.subheadline.weight(.medium))
                        Text(compat.size)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(compat.status.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(compat.status.color == "green" ? .systemGreen : .systemOrange).opacity(0.15))
                        .foregroundStyle(Color(compat.status.color == "green" ? .systemGreen : .systemOrange))
                        .clipShape(Capsule())
                }
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Max tokens info
            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Up to \(result.maxConcurrentTokens) tokens context")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recommendations", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(result.recommendations) { rec in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: rec.icon)
                        .font(.subheadline)
                        .foregroundStyle(LamoTheme.Colors.accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.title)
                            .font(.subheadline.weight(.medium))
                        Text(rec.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(LamoTheme.Colors.accent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Timing

    private var timingSection: some View {
        HStack(spacing: 20) {
            timingItem(label: "CPU", value: result.cpuTime)
            timingItem(label: "GPU", value: result.gpuTime)
            timingItem(label: "Total", value: result.totalTime)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func timingItem(label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%.2fs", value))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var tierColor: Color {
        switch result.aiTierColor {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        default: return .red
        }
    }

    private func scoreLabel(_ gflops: Double) -> String {
        if gflops >= 2.0 { return "Excellent" }
        if gflops >= 1.0 { return "Good" }
        if gflops >= 0.5 { return "Moderate" }
        return "Slow"
    }

    private func scoreColor(_ gflops: Double) -> Color {
        if gflops >= 2.0 { return .green }
        if gflops >= 1.0 { return .blue }
        if gflops >= 0.5 { return .orange }
        return .red
    }
}
