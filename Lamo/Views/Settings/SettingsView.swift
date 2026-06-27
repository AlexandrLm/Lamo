import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var benchmark = DeviceBenchmark()
    @State private var isImportingModel = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var importedModelName = ""
    @State private var isCopyingFile = false
    @State private var showError = false
    @State private var showResetAlert = false
    @State private var activeSection: SettingsSection?
    @Environment(\.dismiss) private var dismiss

    enum SettingsSection: String, CaseIterable {
        case engine = "AI Engine"
        case models = "Models"
        case sampler = "Generation"
        case advanced = "Advanced"
        case device = "Device"
        case privacy = "Privacy"
        case about = "About"
    }

    var body: some View {
        NavigationStack {
            List {
                // Engine picker (compact)
                enginePickerSection

                // All sections as navigation links
                if vm.selectedProviderType == .litertLM {
                    navigationSections
                }

                // Privacy (always visible)
                privacySection

                // About
                aboutSection
            }
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
            .navigationDestination(for: SettingsSection.self) { section in
                sectionView(section)
            }
        }
    }

    // MARK: - Engine Picker

    private var enginePickerSection: some View {
        Section {
            Picker(selection: $vm.selectedProviderType) {
                ForEach(ProviderType.allCases) { provider in
                    HStack {
                        Image(systemName: provider.icon)
                        Text(provider.displayName)
                    }
                    .tag(provider)
                }
            } label: {
                Label("AI Engine", systemImage: "cpu")
            }
            .pickerStyle(.navigationLink)

            if vm.selectedProviderType == .litertLM {
                engineStatusRow
            }
        } footer: {
            if vm.selectedProviderType == .litertLM {
                Text("Runs AI models directly on your device. No internet needed.")
            } else {
                Text("Uses Apple's built-in AI. Requires Apple Intelligence.")
            }
        }
    }

    private var engineStatusRow: some View {
        Group {
            if providerManager.isEngineReady {
                Label("Model loaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else if let error = providerManager.engineError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

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
            }
        }
    }

    private var providerManager: ProviderManager { ProviderManager.shared }

    // MARK: - Navigation Sections

    private var navigationSections: some View {
        Section {
            ForEach(SettingsSection.allCases.filter { $0 != .privacy && $0 != .about }, id: \.self) { section in
                NavigationLink(value: section) {
                    Label {
                        Text(section.rawValue)
                    } icon: {
                        Image(systemName: sectionIcon(section))
                            .foregroundStyle(LamoTheme.Colors.accent)
                    }
                }
            }

            // Import button
            Button {
                isImportingModel = true
            } label: {
                HStack {
                    if isCopyingFile {
                        ProgressView().controlSize(.small)
                        Text("Importing…")
                    } else {
                        Label("Import Model", systemImage: "square.and.arrow.down")
                    }
                }
                .foregroundStyle(LamoTheme.Colors.accent)
            }
            .disabled(isCopyingFile)

            // Reset
            Button {
                showResetAlert = true
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.red)
        }
    }

    private func sectionIcon(_ section: SettingsSection) -> String {
        switch section {
        case .engine: return "cpu"
        case .models: return "internaldrive"
        case .sampler: return "sparkles"
        case .advanced: return "gearshape.2"
        case .device: return "iphone"
        case .privacy: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    // MARK: - Section Views

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        switch section {
        case .models:
            modelsSection
        case .sampler:
            samplerSection
        case .advanced:
            advancedSection
        case .device:
            deviceSection
        default:
            EmptyView()
        }
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        List {
            // Available models
            Section("Downloaded Models") {
                ForEach(PresetModel.allCases) { model in
                    ModelCardView(model: model, downloadManager: downloadManager)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
            }

            // Model picker
            if !vm.availableModels.isEmpty {
                Section("Local Model") {
                    Picker(selection: Binding(
                        get: { vm.selectedModel ?? "" },
                        set: { vm.selectedModel = $0.isEmpty ? nil : $0; vm.loadModelInfo() }
                    )) {
                        Text("Auto-detect").tag("")
                        ForEach(vm.availableModels, id: \.self) { model in
                            Text(vm.displayName(for: model)).tag(model)
                        }
                    } label: {
                        Label("Active Model", systemImage: "internaldrive")
                    }
                }
            }

            // Model info
            if let info = vm.modelInfo {
                Section("Model Info") {
                    LabeledContent("Name", value: info.name)
                    LabeledContent("File Size", value: info.fileSizeString)
                    LabeledContent("Speculative Decoding", value: info.hasSpeculativeDecoding ? "Supported" : "Not Available")
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sampler Section

    private var samplerSection: some View {
        List {
            // Temperature
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", vm.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.temperature, in: 0.0...2.0, step: 0.05)
                        .tint(LamoTheme.Colors.accent)
                    Text("Lower = more focused, higher = more creative")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Sampling")
            } footer: {
                Text("Controls randomness in text generation. 0.7 is a good balance.")
            }

            // Top-K
            Section {
                VStack(alignment: .leading, spacing: 8) {
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
                    Text("Number of top tokens to consider. Lower = more focused.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Top-P
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top-P")
                        Spacer()
                        Text(String(format: "%.2f", vm.topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.topP, in: 0.0...1.0, step: 0.05)
                        .tint(LamoTheme.Colors.accent)
                    Text("Nucleus sampling. 0.95 = consider 95% probability mass.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Reset
            Button {
                vm.resetSamplerDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
            .foregroundStyle(.red)
        }
        .navigationTitle("Generation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        List {
            // Backend
            Section {
                Toggle(isOn: $vm.useGPU) {
                    Label("GPU Acceleration", systemImage: "bolt.fill")
                }
                .tint(LamoTheme.Colors.accent)

                if !vm.useGPU {
                    VStack(alignment: .leading, spacing: 8) {
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
                        Text("More threads = faster but uses more battery")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Compute Backend")
            } footer: {
                Text("GPU (Metal) is faster for most models. CPU uses less battery.")
            }

            // KV-Cache
            Section {
                VStack(alignment: .leading, spacing: 8) {
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
                    Text("Max context window. Higher = longer conversations but more memory.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("KV-Cache")
            } footer: {
                Text("Controls the KV-cache size. Larger values allow longer conversations but use more RAM.")
            }

            // Speculative Decoding
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
                    Text("Uses a draft model to predict multiple tokens at once. Requires model support.")
                }
            }

            // Vision
            Section {
                VStack(alignment: .leading, spacing: 8) {
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
                    Text("Number of visual tokens per image. Higher = better quality but slower.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Vision")
            } footer: {
                Text("Controls image processing quality for multimodal models like Gemma 4.")
            }

            // System Prompt
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
                Text("Instructions the model follows. Changes apply to new conversations only.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        List {
            if let result = benchmark.result {
                VStack(spacing: 12) {
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

                    Divider()

                    HStack(spacing: 0) {
                        statItem("Memory", value: String(format: "%.0f GB", result.ramGB), icon: "memorychip")
                        Spacer()
                        statItem("GPU", value: result.hasGPU ? "Metal" : "None", icon: "gpu")
                        Spacer()
                        statItem("Storage", value: String(format: "%.0f GB", result.storageFreeGB), icon: "internaldrive")
                    }

                    HStack {
                        Text("Compute Speed")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fs", result.computeScore))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(computeLabel(result.computeScore))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(computeColor(result.computeScore).opacity(0.15))
                            .foregroundStyle(computeColor(result.computeScore))
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)

                if !result.recommendations.isEmpty {
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
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fully Private")
                        .font(.body)
                        .fontWeight(.medium)
                    Text("All processing happens on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }

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

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        let ext = url.pathExtension.lowercased()
        guard ext == "litertlm" || ext == "bin" || ext == "tflite" else {
            importError = "Unsupported file type '.\(ext)'. Please select a .litertlm file."
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

    // MARK: - Benchmark Helpers

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

    private func computeLabel(_ seconds: Double) -> String {
        if seconds < 0.5 { return "Fast" }
        if seconds < 1.0 { return "Normal" }
        if seconds < 2.0 { return "Slow" }
        return "Very Slow"
    }

    private func computeColor(_ seconds: Double) -> Color {
        if seconds < 0.5 { return .green }
        if seconds < 1.0 { return .blue }
        if seconds < 2.0 { return .orange }
        return .red
    }
}
