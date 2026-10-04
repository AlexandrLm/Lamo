import SwiftUI

/// Inference settings — sampling, compute engine, performance, system prompt.
/// Compact single-screen layout: one glass card per section, rows separated by dividers.
struct GenerationComputeSection: View {
    @Bindable var vm: SettingsViewModel
    @State private var showSystemPrompt = false
    @State private var selectedPresetID = "assistant"

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
        if vm.samplerAuto { return String(localized: "Balanced") }
        switch vm.samplerTemp {
        case ..<0.5: return String(localized: "Focused · \(String(format: "%.2f", vm.samplerTemp))")
        case 0.5...1.0: return String(localized: "Balanced · \(String(format: "%.2f", vm.samplerTemp))")
        default: return String(localized: "Creative · \(String(format: "%.2f", vm.samplerTemp))")
        }
    }
    private var samplingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Sampling"), icon: "sparkles")
                .padding(.bottom, LamoTheme.Spacing.sm)

            samplerAutoRow

            if !vm.samplerAuto {
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
        .animation(.easeInOut(duration: 0.2), value: vm.samplerAuto)
    }

    private var samplerAutoRow: some View {
        HStack {
            Label("Defaults", systemImage: "slider.horizontal.2.gobackward")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textHigh)
            Spacer()
            Text("Auto")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(vm.samplerAuto ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
            Toggle("", isOn: $vm.samplerAuto)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
        .onChange(of: vm.samplerAuto) { _, newValue in
            if newValue {
                vm.resetSamplerDefaults()
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
                tempBadge(vm.samplerTemp)
            }

            Slider(value: $vm.samplerTemp, in: 0.0...2.0, step: 0.05)
                .tint(tempTint)

            HStack(spacing: 0) {
                rangeLabel(String(localized: "Focused"), active: vm.samplerTemp < 0.5)
                Spacer()
                rangeLabel(String(localized: "Balanced"), active: vm.samplerTemp >= 0.5 && vm.samplerTemp <= 1.0)
                Spacer()
                rangeLabel(String(localized: "Creative"), active: vm.samplerTemp > 1.0)
            }
        }
        .padding(.vertical, 10)
    }

    private var topKRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-K", systemImage: "list.number")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip("\(Int(vm.samplerTopK))")
            }

            Slider(value: $vm.samplerTopK, in: 1...200, step: 1)
                .tint(LamoTheme.Colors.textMedium)

            HStack(spacing: 0) {
                rangeLabel("1", active: vm.samplerTopK <= 20)
                Spacer()
                rangeLabel("200", active: vm.samplerTopK > 80)
            }
        }
        .padding(.vertical, 10)
    }

    private var topPRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-P", systemImage: "circle.dotted")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                valueChip(String(format: "%.2f", vm.samplerTopP))
            }

            Slider(value: $vm.samplerTopP, in: 0.0...1.0, step: 0.05)
                .tint(LamoTheme.Colors.textMedium)

            HStack(spacing: 0) {
                rangeLabel("0", active: vm.samplerTopP <= 0.5)
                Spacer()
                rangeLabel("1", active: vm.samplerTopP >= 0.9)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Engine Card

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Engine"), icon: "cpu")
                .padding(.bottom, LamoTheme.Spacing.sm)

            gpuRow
            ThinDivider()

            if !vm.gpuOn { cpuRow }
            if !vm.gpuOn { ThinDivider() }

            contextRow
            if !vm.contextAuto { contextSlider }
            ThinDivider()
            specDecRow
            ThinDivider()
            visionRow
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .animation(.easeInOut(duration: 0.2), value: vm.gpuOn)
        .animation(.easeInOut(duration: 0.2), value: vm.contextAuto)
    }

    private var gpuRow: some View {
        HStack {
            Label("GPU Acceleration", systemImage: "bolt.fill")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textHigh)
            Spacer()
            Toggle("", isOn: $vm.gpuOn)
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
            Text(vm.contextAuto ? "Auto" : "\(Int(vm.contextTokens))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(vm.contextAuto ? LamoTheme.Colors.textLow : LamoTheme.Colors.textMedium)
            Toggle("", isOn: $vm.contextAuto)
                .labelsHidden()
                .tint(LamoTheme.Colors.accent)
        }
        .padding(.vertical, 10)
    }

    private var contextSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $vm.contextTokens, in: 1024...16384, step: 256)
                .tint(LamoTheme.Colors.textMedium)

            HStack(spacing: 0) {
                Text("1024")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                Spacer()
                Text("\(Int(vm.contextTokens))")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textLow)
                Spacer()
                Text("16384")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
            }
        }
        .padding(.bottom, 10)
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
                        vm.applyPreset(preset)
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
        switch vm.samplerTemp {
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

                Slider(value: $vm.compressionPct, in: 0.2...0.9, step: 0.05) {
                    Text("Threshold")
                }
                .tint(LamoTheme.Colors.accent)

                HStack {
                    Text("Trigger at \(Int(vm.compressionPct * 100))% KV-cache fill")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                    Spacer()
                    Text(vm.compressionPct >= 0.8 ? String(localized: "Late") : vm.compressionPct <= 0.35 ? String(localized: "Early") : String(localized: "Balanced"))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }
            .padding(.vertical, 10)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }
}
