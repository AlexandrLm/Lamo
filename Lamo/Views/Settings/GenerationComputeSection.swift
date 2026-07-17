import SwiftUI

/// Inference settings — sampling, compute engine, performance, system prompt.
/// Compact single-screen layout: one glass card per section, rows separated by dividers.
struct GenerationComputeSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var showSystemPrompt = false

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                samplingCard
                engineCard
                systemPromptRow
                resetButton
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Inference")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sampling Card

    private var samplingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "sparkles", title: "Sampling")

            tempRow
            thinDivider
            topKRow
            thinDivider
            topPRow
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var tempRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                tempBadge(vm.temperature)
            }

            Slider(value: $vm.temperature, in: 0.0...2.0, step: 0.05)
                .tint(tempTint)

            HStack(spacing: 0) {
                rangeLabel("Focused", active: vm.temperature < 0.5)
                Spacer()
                rangeLabel("Balanced", active: vm.temperature >= 0.5 && vm.temperature <= 1.0)
                Spacer()
                rangeLabel("Creative", active: vm.temperature > 1.0)
            }
        }
        .padding(.vertical, 10)
    }

    private var topKRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-K", systemImage: "list.number")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                valueChip("\(vm.topK)")
            }

            Slider(value: Binding(
                get: { Double(vm.topK) },
                set: { vm.topK = Int($0) }
            ), in: 1...200, step: 1)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                rangeLabel("1", active: vm.topK <= 20)
                Spacer()
                rangeLabel("200", active: vm.topK > 80)
            }
        }
        .padding(.vertical, 10)
    }

    private var topPRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-P", systemImage: "circle.dotted")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                valueChip(String(format: "%.2f", vm.topP))
            }

            Slider(value: $vm.topP, in: 0.0...1.0, step: 0.05)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                rangeLabel("0", active: vm.topP <= 0.5)
                Spacer()
                rangeLabel("1", active: vm.topP >= 0.9)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Engine Card

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "cpu", title: "Engine")

            gpuRow
            thinDivider

            if !vm.useGPU { cpuRow }
            if !vm.useGPU { thinDivider }

            contextRow
            thinDivider
            specDecRow
            thinDivider
            visionRow
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .animation(.easeInOut(duration: 0.2), value: vm.useGPU)
        .animation(.easeInOut(duration: 0.2), value: vm.kvCacheAuto)
    }

    private var gpuRow: some View {
        HStack {
            Label("GPU Acceleration", systemImage: "bolt.fill")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $vm.useGPU)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
    }

    private var cpuRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("CPU Threads", systemImage: "arrow.triangle.branch")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                valueChip("\(vm.cpuThreadCount)")
            }

            Slider(value: Binding(
                get: { Double(vm.cpuThreadCount) },
                set: { vm.cpuThreadCount = Int($0) }
            ), in: 1...8, step: 1)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                rangeLabel("Battery", active: vm.cpuThreadCount <= 2)
                Spacer()
                rangeLabel("Speed", active: vm.cpuThreadCount > 5)
            }
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var contextRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Context Window", systemImage: "memorychip")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("", isOn: $vm.kvCacheAuto)
                    .labelsHidden()
                    .tint(LamoTheme.Colors.accent)
                Text(vm.kvCacheAuto ? "Auto" : "\(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(minWidth: 36, alignment: .trailing)
            }

            if !vm.kvCacheAuto {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max Tokens")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Text("\(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens)")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Slider(value: Binding(
                        get: { Double(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens) },
                        set: { vm.maxNumTokens = Int($0) }
                    ), in: 1024...16384, step: 256)
                        .tint(.white.opacity(0.5))
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
    }

    private var specDecRow: some View {
        HStack {
            Label("Spec. Decoding", systemImage: "bolt.speedometer")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(vm.modelInfo?.hasSpeculativeDecoding == true ? .white : .white.opacity(0.35))
            Spacer()
            if vm.modelInfo?.hasSpeculativeDecoding == true {
                Toggle("", isOn: $vm.speculativeDecoding)
                    .labelsHidden()
                    .tint(LamoTheme.Colors.accent)
            } else {
                Text("N/A")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.vertical, 10)
    }

    private var visionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Vision Budget", systemImage: "eye")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)

            Picker("Budget", selection: $vm.visualTokenBudget) {
                Text("70").tag(70)
                Text("140").tag(140)
                Text("280").tag(280)
                Text("560").tag(560)
                Text("1120").tag(1120)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
    }

    // MARK: - System Prompt

    private var systemPromptRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSystemPrompt.toggle()
                }
            } label: {
                HStack {
                    Label("System Prompt", systemImage: "text.bubble")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: showSystemPrompt ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
            }
            .buttonStyle(.plain)

            if showSystemPrompt {
                thinDivider
                    .padding(.horizontal, LamoTheme.Spacing.lg)

                TextEditor(text: $vm.systemPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minHeight: 120, maxHeight: 250)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.sm))
                    .padding(LamoTheme.Spacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            vm.resetSamplerDefaults()
        } label: {
            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Helpers

    private var thinDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LamoTheme.Colors.accent)
            Text(title)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.8))
                .textCase(.uppercase)
        }
        .padding(.bottom, LamoTheme.Spacing.sm)
    }

    private func tempBadge(_ t: Double) -> some View {
        Text(String(format: "%.2f", t))
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tempTint)
            .clipShape(Capsule())
    }

    private var tempTint: Color {
        switch vm.temperature {
        case 0..<0.5:  return .blue.opacity(0.8)
        case 0.5...1.0: return LamoTheme.Colors.accent
        default:        return .orange.opacity(0.8)
        }
    }

    private func valueChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
    }

    private func rangeLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(active ? .white.opacity(0.7) : .white.opacity(0.25))
            .fontWeight(active ? .semibold : .regular)
    }
}
