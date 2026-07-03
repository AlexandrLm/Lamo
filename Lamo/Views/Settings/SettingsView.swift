import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var benchmark = DeviceBenchmark()
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
            List {
                appHeader
                engineSection
                aiSection
                systemSection
                deviceLink
                privacyBadge
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
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
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("Importing model…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial)
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

    // ── App Header ──

    private var appHeader: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [LamoTheme.Colors.accent, LamoTheme.Colors.accent.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lamo")
                        .font(.headline)
                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 2)
            }
            .padding(.vertical, 4)
        }
    }

    // ── Engine Status ──

    private var engineSection: some View {
        Section {
            Group {
                if providerManager.isEngineReady {
                    Label {
                        Text("Model loaded")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolEffect(.bounce, value: providerManager.isEngineReady)
                    }
                    .foregroundStyle(.green)
                } else if let error = providerManager.engineError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.subheadline)

            if let current = vm.selectedModel {
                HStack {
                    Label("Active", systemImage: "bolt.circle.fill")
                        .foregroundStyle(LamoTheme.Colors.accent)
                    Spacer()
                    Text(vm.displayName(for: current))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        } footer: {
            Text("On-device AI. No internet needed.")
        }
    }

    // ── AI Section ──

    private var aiSection: some View {
        Section("AI") {
            NavigationLink(value: SettingsSection.models) {
                Label {
                    HStack {
                        Text("Models")
                        Spacer()
                        if let current = vm.selectedModel {
                            Text(vm.displayName(for: current))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.blue)
                }
            }

            NavigationLink(value: SettingsSection.sampler) {
                Label {
                    HStack {
                        Text("Generation")
                        Spacer()
                        Text("T:\(String(format: "%.1f", vm.temperature)) K:\(vm.topK)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                }
            }

            NavigationLink(value: SettingsSection.memory) {
                Label {
                    HStack {
                        Text("Memory")
                        Spacer()
                        Text("\(MemoryService.shared.totalEntries) facts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "brain")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // ── System Section ──

    private var systemSection: some View {
        Section("System") {
            NavigationLink(value: SettingsSection.advanced) {
                Label("Advanced", systemImage: "gearshape.2")
            }

            Button {
                showResetAlert = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.red)
        }
    }

    // ── Device Link ──

    private var deviceLink: some View {
        Section("Device") {
            NavigationLink(value: SettingsSection.device) {
                Label {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Device Info")
                            if let result = benchmark.result {
                                Text("\(result.chipName) · \(String(format: "%.0f", result.ramGB)) GB RAM")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let result = benchmark.result {
                            tierBadge(result)
                        }
                    }
                } icon: {
                    Image(systemName: "iphone")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // ── Privacy Badge ──

    private var privacyBadge: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fully Private")
                        .fontWeight(.medium)
                    Text("All processing happens on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    // ── About ──

    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://ai.google.dev/edge/litert-lm")!) {
                HStack {
                    Text("LiteRT-LM by Google")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://huggingface.co/litert-community")!) {
                HStack {
                    Text("Models from HuggingFace")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                        get: { vm.selectedModel ?? "" },
                        set: { vm.selectedModel = $0.isEmpty ? nil : $0; vm.loadModelInfo() }
                    )) {
                        Text("Auto-detect").tag("")
                        ForEach(vm.availableModels, id: \.self) { model in
                            Text(vm.displayName(for: model)).tag(model)
                        }
                    } label: {
                        Label("Active Model", systemImage: "bolt.circle.fill")
                    }
                } footer: {
                    Text("Auto-detect picks the best available model.")
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
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
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
            // Temperature with visual indicator
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

                    // Visual range indicator
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

            // Top-K
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

            // Top-P
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
        List {
            if let result = benchmark.result {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.deviceName)
                                .font(.headline)
                            Text(result.chipName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        tierBadge(result)
                    }
                }

                Section("Hardware") {
                    HStack(spacing: 0) {
                        statItem("Memory", value: String(format: "%.1f GB", result.ramGB), icon: "memorychip")
                        Spacer()
                        statItem("GPU Cores", value: result.hasGPU ? "\(result.gpuCoreCount)" : "—", icon: "gpu")
                        Spacer()
                        statItem("Storage", value: String(format: "%.1f GB free", result.storageFreeGB), icon: "internaldrive")
                    }
                }

                Section("Performance") {
                    HStack {
                        Label("CPU", systemImage: "cpu")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        ProgressView(value: min(result.cpuScore / 3.0, 1.0))
                            .tint(scoreColor(result.cpuScore))
                        Spacer(minLength: 8)
                        Text(String(format: "%.2f GFLOPS", result.cpuScore))
                            .font(.subheadline.monospacedDigit())
                        Text(scoreLabel(result.cpuScore))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(scoreColor(result.cpuScore).opacity(0.15))
                            .foregroundStyle(scoreColor(result.cpuScore))
                            .clipShape(Capsule())
                    }

                    if result.hasGPU {
                        HStack {
                            Label("GPU", systemImage: "gpu")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            ProgressView(value: min(result.gpuScore / 5.0, 1.0))
                                .tint(scoreColor(result.gpuScore))
                            Spacer(minLength: 8)
                            Text(String(format: "%.2f GFLOPS", result.gpuScore))
                                .font(.subheadline.monospacedDigit())
                            Text(scoreLabel(result.gpuScore))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(scoreColor(result.gpuScore).opacity(0.15))
                                .foregroundStyle(scoreColor(result.gpuScore))
                                .clipShape(Capsule())
                        }
                    }

                    Divider()

                    HStack {
                        Text("AI Score")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.2f GFLOPS", result.combinedScore))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(LamoTheme.Colors.accent)
                    }
                }

                if !result.recommendations.isEmpty {
                    Section("Recommendations") {
                        ForEach(result.recommendations) { rec in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: rec.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(LamoTheme.Colors.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(rec.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(rec.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if benchmark.isRunning {
                Section {
                    VStack(spacing: 16) {
                        ProgressView(value: benchmark.progress)
                            .tint(LamoTheme.Colors.accent)
                        Text(benchmarkProgressLabel(benchmark.progress))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section {
                Button {
                    Task { await benchmark.runBenchmark() }
                } label: {
                    HStack {
                        if benchmark.isRunning {
                            ProgressView().controlSize(.small)
                            Text("Testing…")
                        } else {
                            Image(systemName: benchmark.result != nil ? "arrow.clockwise" : "gauge.with.dots.fill")
                            Text(benchmark.result != nil ? "Test Again" : "Check Performance")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.medium)
                }
                .disabled(benchmark.isRunning)
                .foregroundStyle(LamoTheme.Colors.accent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

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
        let color: Color = {
            switch result.aiTierColor {
            case "green": return .green
            case "blue": return .blue
            case "orange": return .orange
            default: return .red
            }
        }()

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
}
