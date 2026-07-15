import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var benchmark = DeviceBenchmark()
    @State private var navigateToResults = false
    @Environment(\.modelContext) private var modelContext
    @State private var isImportingModel = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var importedModelName = ""
    @State private var isCopyingFile = false
    @State private var showError = false
    @State private var showResetAlert = false
    @State private var showDeleteModelAlert = false
    @State private var modelToDelete: PresetModel?
    @Environment(\.dismiss) private var dismiss

    private var providerManager: ProviderManager { ProviderManager.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LamoTheme.Spacing.lg) {
                    // ── Hero Status Card ──
                    heroCard
                        .padding(.top, LamoTheme.Spacing.sm)

                    // ── Action Grid ──
                    actionGrid

                    // ── Privacy ──
                    privacyRow

                    // ── About Links ──
                    aboutLinks

                    // ── Footer ──
                    footer
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.bottom, LamoTheme.Spacing.xxxl)
            }
            .background(LamoTheme.Colors.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                vm.refreshModels()
                vm.loadModelInfo()
                MemoryService.shared.setModelContext(modelContext)
            }
            .fileImporter(
                isPresented: $isImportingModel,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleModelImport(result)
            }
            .overlay {
                if isCopyingFile {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Importing model…")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(28)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError { Text(error) }
            }
            .alert("Model Imported", isPresented: $importSuccess) {
                Button("Use Now") {
                    vm.selectedModel = importedModelName
                    vm.refreshModels()
                    vm.loadModelInfo()
                }
                Button("Later", role: .cancel) { vm.refreshModels() }
            } message: {
                Text("\(vm.displayName(for: importedModelName)) is ready to use.")
            }
            .alert("Reset Settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { vm.resetAllDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will restore all settings to their defaults.")
            }
            .alert("Delete Model?", isPresented: $showDeleteModelAlert) {
                Button("Delete", role: .destructive) {
                    if let model = modelToDelete {
                        downloadManager.deleteModel(model)
                    }
                }
                Button("Cancel", role: .cancel) { modelToDelete = nil }
            } message: {
                if let model = modelToDelete {
                    Text("Remove \(model.displayName) from your device?")
                }
            }
            .navigationDestination(for: SettingsSection.self) { section in
                sectionView(section)
            }
        }
    }

    // MARK: - Sections

    enum SettingsSection: String, CaseIterable, Hashable {
        case engine = "AI Engine"
        case models = "Models"
        case sampler = "Generation"
        case memory = "Memory"
        case advanced = "Advanced"
        case device = "Device"
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
            // Status line
            HStack(spacing: LamoTheme.Spacing.sm) {
                statusDot
                Text(statusLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                Spacer()
            }

            // Model name
            if let current = vm.selectedModel {
                Text(vm.displayName(for: current))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No model loaded")
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Subtitle
            Text("On-device · No internet")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))

            // Device info
            if let result = benchmark.result {
                HStack(spacing: LamoTheme.Spacing.md) {
                    deviceStat(value: result.chipName, label: "CHIP")
                    deviceStat(
                        value: String(format: "%.0f GB", result.ramGB),
                        label: "RAM"
                    )
                    Spacer()
                    tierBadge(result)
                }
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    @ViewBuilder
    private var statusDot: some View {
        if providerManager.isEngineReady {
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
        } else if providerManager.engineError != nil {
            Circle()
                .fill(.white.opacity(0.5))
                .frame(width: 8, height: 8)
        } else {
            ProgressView()
                .controlSize(.mini)
                .tint(.white.opacity(0.6))
        }
    }

    private var statusLabel: String {
        if providerManager.isEngineReady {
            return "Ready"
        } else if let error = providerManager.engineError {
            return "Error"
        } else {
            return "Loading"
        }
    }

    private func deviceStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)
        }
    }

    // MARK: - Action Grid

    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md),
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md)
        ]

        return LazyVGrid(columns: columns, spacing: LamoTheme.Spacing.md) {
            // Models
            NavigationLink(value: SettingsSection.models) {
                gridCard(
                    icon: "internaldrive",
                    title: "Models",
                    subtitle: gridSubtitle_models
                )
            }

            // Generation
            NavigationLink(value: SettingsSection.sampler) {
                gridCard(
                    icon: "sparkles",
                    title: "Generation",
                    subtitle: "T:\(String(format: "%.1f", vm.temperature)) K:\(vm.topK)"
                )
            }

            // Memory
            NavigationLink(value: SettingsSection.memory) {
                gridCard(
                    icon: "brain",
                    title: "Memory",
                    subtitle: "\(MemoryService.shared.totalEntries) facts"
                )
            }

            // Web Search
            NavigationLink {
                WebSearchSettings()
            } label: {
                gridCard(
                    icon: "globe",
                    title: "Web Search",
                    subtitle: ProviderManager.shared.braveAPIKey != nil
                        ? "Brave + SearXNG"
                        : "SearXNG"
                )
            }

            // Device
            NavigationLink(value: SettingsSection.device) {
                gridCard(
                    icon: "iphone",
                    title: "Device",
                    subtitle: gridSubtitle_device
                )
            }

            // Advanced
            NavigationLink(value: SettingsSection.advanced) {
                gridCard(
                    icon: "gearshape.2",
                    title: "Advanced",
                    subtitle: gridSubtitle_advanced
                )
            }
        }
    }

    private var gridSubtitle_models: String {
        if let current = vm.selectedModel {
            return vm.displayName(for: current)
        }
        return "Select model"
    }

    private var gridSubtitle_device: String {
        if let result = benchmark.result {
            return "\(result.chipName) · \(String(format: "%.0f", result.ramGB)) GB"
        }
        return "Not benchmarked"
    }

    private var gridSubtitle_advanced: String {
        vm.useGPU ? "GPU · Auto" : "CPU · \(vm.cpuThreadCount) threads"
    }

    private func gridCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))

            Spacer(minLength: 0)

            Text(title)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LamoTheme.Spacing.md)
        .frame(height: 110)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    // MARK: - Privacy Row

    private var privacyRow: some View {
        HStack(spacing: LamoTheme.Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))

            Text("All processing on device")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)

            Spacer()
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - About Links

    private var aboutLinks: some View {
        HStack(spacing: LamoTheme.Spacing.lg) {
            Link(destination: URL(string: "https://ai.google.dev/edge/litert-lm")!) {
                HStack(spacing: 4) {
                    Text("LiteRT-LM")
                        .font(.system(.caption2, design: .monospaced))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.3))
            }

            Link(destination: URL(string: "https://huggingface.co/litert-community")!) {
                HStack(spacing: 4) {
                    Text("HuggingFace")
                        .font(.system(.caption2, design: .monospaced))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.white.opacity(0.3))
            }

            Spacer()

            Button {
                showResetAlert = true
            } label: {
                Text("Reset")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Lamo · v\(appVersionShort)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.15))
        }
        .padding(.top, LamoTheme.Spacing.lg)
    }

    // MARK: - Navigation

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        switch section {
        case .models:
            modelsSection
        case .sampler:
            samplerSection
        case .memory:
            memorySection
        case .advanced:
            advancedSection
        case .device:
            deviceSection
        default:
            EmptyView()
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        List {
            if !vm.availableModels.isEmpty {
                Section {
                    Picker(selection: Binding(
                        get: { vm.selectedModel ?? vm.availableModels.first ?? "" },
                        set: { vm.selectedModel = $0; vm.loadModelInfo() }
                    )) {
                        ForEach(vm.availableModels, id: \.self) { model in
                            Text(vm.displayName(for: model)).tag(model)
                        }
                    } label: {
                        Label("Active Model", systemImage: "bolt.circle.fill")
                    }
                }
            }

            Section("Available Models") {
                ForEach(PresetModel.allCases) { model in
                    ModelCardView(
                        model: model,
                        downloadManager: downloadManager,
                        isActiveModel: vm.selectedModel?.contains(model.filename.replacingOccurrences(of: ".litertlm", with: "")) == true
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            Section {
                Button {
                    isImportingModel = true
                } label: {
                    HStack {
                        if isCopyingFile {
                            ProgressView().controlSize(.small)
                            Text("Importing…")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import from Files")
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(.black)
                .disabled(isCopyingFile)
            } footer: {
                Text(".litertlm, .bin, or .tflite model files.")
            }

            let localModels = vm.availableModels.filter { path in
                !PresetModel.allCases.contains { $0.filename == (path as NSString).lastPathComponent }
            }
            if !localModels.isEmpty {
                Section("Imported Models") {
                    ForEach(localModels, id: \.self) { path in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.displayName(for: path))
                                    .font(.body)
                                Text((path as NSString).lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.selectedModel == path {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(LamoTheme.Colors.accent)
                            }
                        }
                    }
                }
            }

            // Storage info
            storageSection

            if let info = vm.modelInfo {
                Section("Model Info") {
                    LabeledContent("Name", value: info.name)
                    LabeledContent("File Size", value: info.fileSizeString)
                    LabeledContent("Speculative Decoding", value: info.hasSpeculativeDecoding ? "Supported" : "Not Available")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Generation

    private var samplerSection: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", vm.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $vm.temperature, in: 0.0...2.0, step: 0.05)
                        .tint(LamoTheme.Colors.accent)

                    HStack(spacing: 0) {
                        Text("Focused")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if vm.temperature >= 0.5 && vm.temperature <= 1.0 {
                            Text("Balanced")
                                .font(.caption2)
                                .foregroundStyle(LamoTheme.Colors.accent)
                                .fontWeight(.medium)
                        } else {
                            Text("Balanced")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("Creative")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text("0.7 is a good balance.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top-K")
                        Spacer()
                        Text("\(vm.topK)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(vm.topK) },
                        set: { vm.topK = Int($0) }
                    ), in: 1...100, step: 1)
                        .tint(LamoTheme.Colors.accent)

                    HStack(spacing: 0) {
                        Text("Focused")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Diverse")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text("Number of top tokens to consider.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top-P")
                        Spacer()
                        Text(String(format: "%.2f", vm.topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.topP, in: 0.0...1.0, step: 0.05)
                        .tint(LamoTheme.Colors.accent)

                    HStack(spacing: 0) {
                        Text("Narrow")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("Broad")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                Text("Nucleus sampling probability mass.")
            }

            Button {
                vm.resetSamplerDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.red)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Generation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Memory

    private var memorySection: some View {
        List {
            Section {
                Toggle(isOn: $vm.memoryEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember Facts")
                        Text("AI extracts key facts from conversations")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel("Memory")
                .tint(LamoTheme.Colors.accent)
            } footer: {
                Text("Facts are injected into context for future conversations.")
            }

            if vm.memoryEnabled {
                Section {
                    HStack {
                        Label("Total Facts", systemImage: "brain")
                        Spacer()
                        Text("\(MemoryService.shared.totalEntries)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                let facts = MemoryService.shared.allFacts
                if !facts.isEmpty {
                    Section("What AI Remembers") {
                        ForEach(facts, id: \.id) { fact in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "text.quote")
                                    .font(.caption)
                                    .foregroundStyle(LamoTheme.Colors.accent)
                                    .frame(width: 16)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.text)
                                        .font(.subheadline)
                                        .textSelection(.enabled)

                                    Text(fact.timestamp, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                MemoryService.shared.deleteFact(facts[index])
                            }
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "No Facts Yet",
                            systemImage: "brain",
                            description: Text("Facts will appear as you chat.")
                        )
                    }
                }

                Section {
                    Button(role: .destructive) {
                        MemoryService.shared.clearAll()
                    } label: {
                        Label("Clear All Facts", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        List {
            Section {
                Toggle(isOn: $vm.useGPU) {
                    Label("GPU Acceleration", systemImage: "bolt.fill")
                }
                .accessibilityLabel("GPU acceleration")
                .tint(LamoTheme.Colors.accent)

                if !vm.useGPU {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("CPU Threads")
                            Spacer()
                            Text("\(vm.cpuThreadCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(vm.cpuThreadCount) },
                            set: { vm.cpuThreadCount = Int($0) }
                        ), in: 1...8, step: 1)
                            .tint(LamoTheme.Colors.accent)

                        HStack(spacing: 0) {
                            Text("Battery")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("Speed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("Compute Backend")
            } footer: {
                Text("GPU (Metal) is faster for most models.")
            }

            Section {
                Toggle(isOn: $vm.kvCacheAuto) {
                    Label("Auto (Recommended)", systemImage: "wand.and.stars")
                }
                .tint(LamoTheme.Colors.accent)

                if !vm.kvCacheAuto {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(vm.maxNumTokens)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(vm.maxNumTokens) },
                            set: { vm.maxNumTokens = Int($0) }
                        ), in: 1024...16384, step: 256)
                            .tint(LamoTheme.Colors.accent)

                        HStack(spacing: 0) {
                            Text("Short")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("Long")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Text("KV-Cache")
            } footer: {
                if vm.kvCacheAuto {
                    Text("Uses model's recommended context size.")
                } else {
                    Text("4096 is a good default.")
                }
            }

            if vm.modelInfo?.hasSpeculativeDecoding == true {
                Section {
                    Toggle(isOn: $vm.speculativeDecoding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Enable", systemImage: "bolt.speedometer")
                            Text("Up to 3x faster generation")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(LamoTheme.Colors.accent)
                } header: {
                    Text("Speculative Decoding")
                } footer: {
                    Text("Uses a draft model to predict multiple tokens.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Visual Token Budget")
                        Spacer()
                        Text("\(vm.visualTokenBudget)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Picker("Budget", selection: $vm.visualTokenBudget) {
                        Text("70 (Fast)").tag(70)
                        Text("140").tag(140)
                        Text("280 (Balanced)").tag(280)
                        Text("560 (Default)").tag(560)
                        Text("1120 (Best)").tag(1120)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Vision")
            } footer: {
                Text("Image processing quality for multimodal models.")
            }

            Section {
                TextEditor(text: $vm.systemPrompt)
                    .font(.subheadline)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.visible)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Applies to new conversations only.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Device

    private var deviceSection: some View {
        Group {
            if benchmark.result != nil {
                // Result already exists — show details directly
                BenchmarkResultView(result: benchmark.result!)
                    .navigationTitle("Benchmark Results")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task {
                                    await benchmark.runBenchmark()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(benchmark.isRunning)
                        }
                    }
            } else if benchmark.isRunning {
                // Running — show progress
                List {
                    Section {
                        VStack(spacing: 20) {
                            ProgressView(value: benchmark.progress)
                                .tint(LamoTheme.Colors.accent)
                            Text(benchmarkProgressLabel(benchmark.progress))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                // No result yet — show start button
                List {
                    Section {
                        Button {
                            Task { await benchmark.runBenchmark() }
                        } label: {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .font(.body)
                                Text("Start Benchmark")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [LamoTheme.Colors.accent, LamoTheme.Colors.accent.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } footer: {
                        Text("Takes about 5–10 seconds. Tests CPU, GPU, memory and Neural Engine.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Quick Stat

    private func quickStat(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Phase Indicator

    private func phaseIndicator(_ phase: DeviceBenchmark.BenchmarkPhase, current: DeviceBenchmark.BenchmarkPhase) -> some View {
        let phases = DeviceBenchmark.BenchmarkPhase.allCases.filter { $0 != .idle }
        guard let currentIndex = phases.firstIndex(where: { $0 == current }),
              let phaseIndex = phases.firstIndex(where: { $0 == phase }) else {
            return AnyView(EmptyView())
        }

        let isComplete = phaseIndex < currentIndex
        let isCurrent = phaseIndex == currentIndex

        return AnyView(
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isComplete ? LamoTheme.Colors.accent : (isCurrent ? LamoTheme.Colors.accent.opacity(0.2) : Color(.tertiarySystemFill)))
                        .frame(width: 28, height: 28)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    } else if isCurrent {
                        ProgressView()
                            .tint(LamoTheme.Colors.accent)
                            .controlSize(.mini)
                    } else {
                        Image(systemName: phase.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(phase.rawValue)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(isCurrent ? LamoTheme.Colors.accent : Color(.tertiaryLabel))
            }
        )
    }

    // MARK: - Helpers

    private var appVersionShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private func benchmarkProgressLabel(_ progress: Double) -> String {
        switch progress {
        case 0..<0.15: return "Collecting device info…"
        case 0.15..<0.55: return "Testing CPU performance…"
        case 0.55..<0.85: return "Testing GPU performance…"
        case 0.85..<1.0: return "Analyzing results…"
        default: return "Done!"
        }
    }

    @ViewBuilder
    private func tierBadge(_ result: DeviceBenchmark.BenchmarkResult) -> some View {
        let color = tierColor(result.aiTierColor)

        HStack(spacing: 4) {
            Image(systemName: result.aiTierIcon)
                .font(.caption)
            Text(result.aiTierLabel)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func statItem(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tierColor(_ colorString: String) -> Color {
        switch colorString {
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

    // MARK: - Model Import

    private func handleModelImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        let ext = url.pathExtension.lowercased()
        guard ext == "litertlm" || ext == "bin" || ext == "tflite" else {
            importError = "Unsupported file type '.\(ext)'. Select a .litertlm file."
            showError = true
            return
        }

        isCopyingFile = true
        Task.detached {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let modelsDir = documents.appendingPathComponent("models")
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            let fileName = url.lastPathComponent
            let destination = modelsDir.appendingPathComponent(fileName)

            do {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)

                await MainActor.run {
                    self.isCopyingFile = false
                    self.importedModelName = fileName
                    self.importSuccess = true
                }
            } catch {
                await MainActor.run {
                    self.isCopyingFile = false
                    self.importError = "Import failed: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section {
            LabeledContent("Location", value: "On My iPhone → Lamo → models")

            let totalSize = calculateModelsSize()
            if totalSize > 0 {
                LabeledContent("Used Space", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
            }

            if let freeSpace = getFreeSpace() {
                LabeledContent("Available", value: ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))
            }

            Button {
                openModelsFolder()
            } label: {
                Label("Open in Files", systemImage: "folder")
                    .foregroundStyle(.white.opacity(0.7))
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Models are stored in the Files app under On My iPhone → Lamo → models. You can also add .litertlm files there manually.")
        }
    }

    // MARK: - Storage Helpers

    private func calculateModelsSize() -> Int64 {
        let modelsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("models")
        guard let files = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for file in files where file.pathExtension == "litertlm" || file.pathExtension == "bin" || file.pathExtension == "tflite" {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    private func getFreeSpace() -> Int64? {
        let modelsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let values = try? modelsDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) {
            return values.volumeAvailableCapacityForImportantUsage
        }
        return nil
    }

    private func openModelsFolder() {
        let modelsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("models")
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        // Open in Files app using the folder URL
        UIApplication.shared.open(modelsDir)
    }
}
