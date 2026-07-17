import SwiftUI
import LiteRTLM

/// Advanced settings section — GPU, CPU threads, KV-cache, speculative decoding, vision, system prompt.
/// Extracted from SettingsView for maintainability.
struct AdvancedSettingsSection: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                computeBackendCard
                kvCacheCard
                if vm.modelInfo?.hasSpeculativeDecoding == true {
                    speculativeDecodingCard
                }
                visionCard
                systemPromptCard
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var computeBackendCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("Compute Backend")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            Toggle(isOn: $vm.useGPU) {
                Label("GPU Acceleration", systemImage: "bolt.fill")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("GPU acceleration")
            .tint(.white.opacity(0.7))

            if !vm.useGPU {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("CPU Threads")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(vm.cpuThreadCount)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Slider(value: Binding(
                        get: { Double(vm.cpuThreadCount) },
                        set: { vm.cpuThreadCount = Int($0) }
                    ), in: 1...8, step: 1)
                        .tint(.white.opacity(0.5))

                    HStack(spacing: 0) {
                        Text("Battery")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        Text("Speed")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Text("GPU (Metal) is faster for most models.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var kvCacheCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("KV-Cache")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            Toggle(isOn: $vm.kvCacheAuto) {
                Label("Auto (Recommended)", systemImage: "wand.and.stars")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .tint(.white.opacity(0.7))

            if !vm.kvCacheAuto {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Max Tokens")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(vm.maxNumTokens)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Slider(value: Binding(
                        get: { Double(vm.maxNumTokens) },
                        set: { vm.maxNumTokens = Int($0) }
                    ), in: 1024...16384, step: 256)
                        .tint(.white.opacity(0.5))

                    HStack(spacing: 0) {
                        Text("Short")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        Text("Long")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if vm.kvCacheAuto {
                Text("Uses model's recommended context size.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                Text("4096 is a good default.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var speculativeDecodingCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("Speculative Decoding")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            Toggle(isOn: $vm.speculativeDecoding) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Enable", systemImage: "bolt.speedometer")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Up to 3x faster generation")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .tint(.white.opacity(0.7))

            Text("Uses a draft model to predict multiple tokens.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var visionCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("Vision")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            HStack {
                Text("Visual Token Budget")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(vm.visualTokenBudget)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Picker("Budget", selection: $vm.visualTokenBudget) {
                Text("70 (Fast)").tag(70)
                Text("140").tag(140)
                Text("280 (Balanced)").tag(280)
                Text("560 (Default)").tag(560)
                Text("1120 (Best)").tag(1120)
            }
            .pickerStyle(.segmented)

            Text("Image processing quality for multimodal models.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var systemPromptCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("System Prompt")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            TextEditor(text: $vm.systemPrompt)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.sm))

            Text("Applies to new conversations only.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }
}
