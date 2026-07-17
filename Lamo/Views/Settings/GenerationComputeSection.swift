import SwiftUI

/// Inference settings — sampling, compute engine, performance, system prompt.
/// Compact single-screen layout: one glass card per section, rows separated by dividers.
struct GenerationComputeSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var showSystemPrompt = false

    // Mirror VM toggles/values so conditional content + sliders re-render reliably.
    // @Observable computed properties backed by UserDefaults don't always
    // trigger view updates through the Binding projection.
    @State private var contextAuto: Bool
    @State private var gpuOn: Bool
    @State private var contextTokens: Double
    @State private var samplerAuto: Bool
    @State private var samplerTemp: Double
    @State private var samplerTopK: Double
    @State private var samplerTopP: Double

    init(vm: SettingsViewModel) {
        self.vm = vm
        _contextAuto = State(initialValue: vm.kvCacheAuto)
        _gpuOn = State(initialValue: vm.useGPU)
        _contextTokens = State(initialValue: Double(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens))
        _samplerAuto = State(initialValue: vm.temperature == 1.0 && vm.topK == 64 && vm.topP == 0.95)
        _samplerTemp = State(initialValue: vm.temperature)
        _samplerTopK = State(initialValue: Double(vm.topK))
        _samplerTopP = State(initialValue: vm.topP)
    }

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
    private var samplingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "sparkles", title: "Sampling")

            samplerAutoRow

            if !samplerAuto {
                thinDivider
                tempRow
                thinDivider
                topKRow
                thinDivider
                topPRow
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .animation(.easeInOut(duration: 0.2), value: samplerAuto)
    }

    private var samplerAutoRow: some View {
        HStack {
            Label("Defaults", systemImage: "slider.horizontal.2.gobackward")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Text("Auto")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(samplerAuto ? 0.5 : 0.25))
            Toggle("", isOn: $samplerAuto)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .onChange(of: samplerAuto) { _, newValue in
            if newValue {
                vm.resetSamplerDefaults()
                samplerTemp = 1.0
                samplerTopK = 64
                samplerTopP = 0.95
            }
        }
    }

    private var tempRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                tempBadge(samplerTemp)
            }

            Slider(value: $samplerTemp, in: 0.0...2.0, step: 0.05)
                .tint(tempTint)

            HStack(spacing: 0) {
                rangeLabel("Focused", active: samplerTemp < 0.5)
                Spacer()
                rangeLabel("Balanced", active: samplerTemp >= 0.5 && samplerTemp <= 1.0)
                Spacer()
                rangeLabel("Creative", active: samplerTemp > 1.0)
            }
        }
        .padding(.vertical, 10)
        .onChange(of: samplerTemp) { _, newValue in
            vm.temperature = newValue
        }
    }

    private var topKRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-K", systemImage: "list.number")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                valueChip("\(Int(samplerTopK))")
            }

            Slider(value: $samplerTopK, in: 1...200, step: 1)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                rangeLabel("1", active: samplerTopK <= 20)
                Spacer()
                rangeLabel("200", active: samplerTopK > 80)
            }
        }
        .padding(.vertical, 10)
        .onChange(of: samplerTopK) { _, newValue in
            vm.topK = Int(newValue)
        }
    }

    private var topPRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-P", systemImage: "circle.dotted")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                valueChip(String(format: "%.2f", samplerTopP))
            }

            Slider(value: $samplerTopP, in: 0.0...1.0, step: 0.05)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                rangeLabel("0", active: samplerTopP <= 0.5)
                Spacer()
                rangeLabel("1", active: samplerTopP >= 0.9)
            }
        }
        .padding(.vertical, 10)
        .onChange(of: samplerTopP) { _, newValue in
            vm.topP = newValue
        }
    }

    // MARK: - Engine Card

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "cpu", title: "Engine")

            gpuRow
            thinDivider

            if !gpuOn { cpuRow }
            if !gpuOn { thinDivider }

            contextRow
            if !contextAuto { contextSlider }
            thinDivider
            specDecRow
            thinDivider
            visionRow
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .animation(.easeInOut(duration: 0.2), value: gpuOn)
        .animation(.easeInOut(duration: 0.2), value: contextAuto)
    }

    private var gpuRow: some View {
        HStack {
            Label("GPU Acceleration", systemImage: "bolt.fill")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $gpuOn)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .onChange(of: gpuOn) { _, newValue in
            vm.useGPU = newValue
        }
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
        HStack {
            Label("Context Window", systemImage: "memorychip")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Text(contextAuto ? "Auto" : "\(Int(contextTokens))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(contextAuto ? 0.5 : 0.7))
            Toggle("", isOn: $contextAuto)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .onChange(of: contextAuto) { _, newValue in
            vm.kvCacheAuto = newValue
            if !newValue {
                contextTokens = Double(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens)
            }
        }
    }

    private var contextSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $contextTokens, in: 1024...16384, step: 256)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                Text("1024")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                Spacer()
                Text("\(Int(contextTokens))")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("16384")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .padding(.bottom, 10)
        .onChange(of: contextTokens) { _, newValue in
            vm.maxNumTokens = Int(newValue)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
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
            samplerAuto = true
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
        switch samplerTemp {
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
