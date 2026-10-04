import SwiftUI

/// Inference settings — sampling, compute engine, performance, system prompt.
/// Compact single-screen layout: one glass card per section, rows separated by dividers.
struct GenerationComputeSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var showSystemPrompt = false
    @State private var selectedPresetID = "assistant"

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
    @State private var compressionPct: Double = 0.6

    init(vm: SettingsViewModel) {
        self.vm = vm
        _contextAuto = State(initialValue: vm.kvCacheAuto)
        _gpuOn = State(initialValue: vm.useGPU)
        _contextTokens = State(initialValue: Double(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens))
        _samplerAuto = State(initialValue: vm.temperature == 0.7 && vm.topK == 64 && vm.topP == 0.95)
        _samplerTemp = State(initialValue: vm.temperature)
        _samplerTopK = State(initialValue: Double(vm.topK))
        _samplerTopP = State(initialValue: vm.topP)
        _compressionPct = State(initialValue: ProviderManager.shared.compressionThreshold)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                samplingCard

                if vm.isLiteRTSelected {
                    engineCard
                }
                compressionCard

                systemPromptRow
                resetButton
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Inference")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(samplerStyleName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
            }
        }
    }

    /// Человеческое имя стиля вместо сырых T/K/P в тулбаре.
    private var samplerStyleName: String {
        if samplerAuto { return String(localized: "Balanced") }
        switch samplerTemp {
        case ..<0.5: return String(localized: "Focused · \(String(format: "%.2f", samplerTemp))")
        case 0.5...1.0: return String(localized: "Balanced · \(String(format: "%.2f", samplerTemp))")
        default: return String(localized: "Creative · \(String(format: "%.2f", samplerTemp))")
        }
    }
    private var samplingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Sampling"), icon: "sparkles")
                .padding(.bottom, LamoTheme.Spacing.sm)

            samplerAutoRow

            if !samplerAuto {
                ThinDivider()
                tempRow
                ThinDivider()
                topKRow
                ThinDivider()
                topPRow
            }

            // Apple Intelligence honors temperature only (clamped to 0–1);
            // Top-K / Top-P are LiteRT-only and stay saved for when you switch back.
            if !vm.isLiteRTSelected {
                ThinDivider()
                Text("Apple Intelligence uses temperature only (0–1). Top-K / Top-P apply to LiteRT-LM.")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .padding(.vertical, 10)
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
                .foregroundStyle(LamoTheme.Colors.textHigh)
            Spacer()
            Text("Auto")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(samplerAuto ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
            Toggle("", isOn: $samplerAuto)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .onChange(of: samplerAuto) { _, newValue in
            if newValue {
                vm.resetSamplerDefaults()
                samplerTemp = 0.7
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
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                tempBadge(samplerTemp)
            }

            Slider(value: $samplerTemp, in: 0.0...2.0, step: 0.05)
                .tint(tempTint)

            HStack(spacing: 0) {
                rangeLabel(String(localized: "Focused"), active: samplerTemp < 0.5)
                Spacer()
                rangeLabel(String(localized: "Balanced"), active: samplerTemp >= 0.5 && samplerTemp <= 1.0)
                Spacer()
                rangeLabel(String(localized: "Creative"), active: samplerTemp > 1.0)
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
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip("\(Int(samplerTopK))")
            }

            Slider(value: $samplerTopK, in: 1...200, step: 1)
                .tint(LamoTheme.Colors.textMedium)

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
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip(String(format: "%.2f", samplerTopP))
            }

            Slider(value: $samplerTopP, in: 0.0...1.0, step: 0.05)
                .tint(LamoTheme.Colors.textMedium)

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
            SectionHeader(title: String(localized: "Engine"), icon: "cpu")
                .padding(.bottom, LamoTheme.Spacing.sm)

            gpuRow
            ThinDivider()

            if !gpuOn { cpuRow }
            if !gpuOn { ThinDivider() }

            contextRow
            if !contextAuto { contextSlider }
            ThinDivider()
            specDecRow
            ThinDivider()
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
                .foregroundStyle(LamoTheme.Colors.textHigh)
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
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip("\(vm.cpuThreadCount)")
            }

            Slider(value: Binding(
                get: { Double(vm.cpuThreadCount) },
                set: { vm.cpuThreadCount = Int($0) }
            ), in: 1...Double(max(4, ProcessInfo.processInfo.processorCount)), step: 1)
                .tint(LamoTheme.Colors.textMedium)

            HStack(spacing: 0) {
                rangeLabel(String(localized: "Battery"), active: vm.cpuThreadCount <= 2)
                Spacer()
                rangeLabel(String(localized: "Speed"), active: vm.cpuThreadCount > 5)
            }

            Text("Takes effect after the engine restarts automatically")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var contextRow: some View {
        HStack {
            Label("Context Window", systemImage: "memorychip")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textHigh)
            Spacer()
            Text(contextAuto ? "Auto" : "\(Int(contextTokens))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(contextAuto ? LamoTheme.Colors.textLow : LamoTheme.Colors.textMedium)
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
                .tint(LamoTheme.Colors.textMedium)

            HStack(spacing: 0) {
                Text("1024")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                Spacer()
                Text("\(Int(contextTokens))")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textLow)
                Spacer()
                Text("16384")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
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
                .foregroundStyle(vm.modelInfo?.hasSpeculativeDecoding == true ? LamoTheme.Colors.textHigh : LamoTheme.Colors.textLow)
            Spacer()
            if vm.modelInfo?.hasSpeculativeDecoding == true {
                Toggle("", isOn: $vm.speculativeDecoding)
                    .labelsHidden()
                    .tint(LamoTheme.Colors.accent)
            } else {
                Text("N/A")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
            }
        }
        .padding(.vertical, 10)
    }

    private var visionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Vision Budget", systemImage: "eye")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip(visionLabel(for: vm.visualTokenBudget))
            }

            Picker("Budget", selection: $vm.visualTokenBudget) {
                Text("Eco").tag(70)
                Text("Low").tag(140)
                Text("Balanced").tag(280)
                Text("High").tag(560)
                Text("Max").tag(1120)
            }
            .pickerStyle(.segmented)

            Text("\(vm.visualTokenBudget) tokens per image — higher sees better, answers slower")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
        }
        .padding(.vertical, 10)
    }

    private func visionLabel(for budget: Int) -> String {
        switch budget {
        case ..<100: return "Eco"
        case ..<200: return "Low"
        case ..<400: return "Balanced"
        case ..<800: return "High"
        default: return "Max"
        }
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
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                    Spacer()
                    Image(systemName: showSystemPrompt ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                }
                .padding(LamoTheme.Spacing.lg)
            }
            .buttonStyle(.plain)

            if showSystemPrompt {
                ThinDivider()
                    .padding(.horizontal, LamoTheme.Spacing.lg)

                // Preset picker
                HStack {
                    Label("Preset", systemImage: "rectangle.stack")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                    Spacer()
                    Picker("Preset", selection: $selectedPresetID) {
                        ForEach(PromptPreset.allPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(LamoTheme.Colors.accent)
                    .onChange(of: selectedPresetID) { _, newID in
                        guard let preset = PromptPreset.preset(id: newID) else { return }
                        vm.systemPrompt = PromptPreset.fullPrompt(for: preset)
                        if let temp = preset.temperature { vm.temperature = temp }
                        if let topP = preset.topP { vm.topP = topP }
                        samplerTemp = vm.temperature
                        samplerTopK = Double(vm.topK)
                        samplerTopP = vm.topP
                        samplerAuto = vm.temperature == 0.7 && vm.topK == 64 && vm.topP == 0.95
                    }
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.top, LamoTheme.Spacing.sm)

                TextEditor(text: $vm.systemPrompt)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .frame(minHeight: 120, maxHeight: 250)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(LamoTheme.Colors.fillSubtle)
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
            // Синхронизируем зеркала — раньше слайдеры залипали на старых значениях.
            samplerTemp = 0.7
            samplerTopK = 64
            samplerTopP = 0.95
            samplerAuto = true
        } label: {
            Label("Reset Sampling", systemImage: "arrow.counterclockwise")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Helpers

    private func tempBadge(_ t: Double) -> some View {
        Text(String(format: "%.2f", t))
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.white)
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
            .foregroundStyle(LamoTheme.Colors.textHigh)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(LamoTheme.Colors.fillStrong)
            .clipShape(Capsule())
    }

    private func rangeLabel(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(active ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
            .fontWeight(active ? .semibold : .regular)
    }

    private var compressionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Auto-Compression"), icon: "compress")
                .padding(.bottom, LamoTheme.Spacing.sm)

            VStack(alignment: .leading, spacing: 4) {
                Text("Automatically summarize conversation when context fills up")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textLow)
                    .fixedSize(horizontal: false, vertical: true)

                Slider(value: $compressionPct, in: 0.2...0.9, step: 0.05) {
                    Text("Threshold")
                }
                .tint(LamoTheme.Colors.accent)

                HStack {
                    Text("Trigger at \(Int(compressionPct * 100))% KV-cache fill")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                    Spacer()
                    Text(compressionPct >= 0.8 ? String(localized: "Late") : compressionPct <= 0.35 ? String(localized: "Early") : String(localized: "Balanced"))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }
            .padding(.vertical, 10)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .onChange(of: compressionPct) { _, newValue in
            ProviderManager.shared.compressionThreshold = newValue
        }
    }
}
