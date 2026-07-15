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
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.lg) {
                // ── Hero: Active Model ──
                modelsHeroCard

                // ── Library: Downloaded Models ──
                let downloadedPresets = PresetModel.allCases.filter { $0.isDownloaded }
                let localModels = vm.availableModels.filter { path in
                    !PresetModel.allCases.contains { $0.filename == (path as NSString).lastPathComponent }
                }
                let hasDownloadedModels = !downloadedPresets.isEmpty || !localModels.isEmpty

                if hasDownloadedModels {
                    VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                        HStack {
                            Text("Library")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(downloadedPresets.count + localModels.count) models")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.2))
                        }

                        ForEach(downloadedPresets) { model in
                            modelLibraryRow(model: model)
                        }

                        ForEach(localModels, id: \.self) { path in
                            importedModelRow(path: path)
                        }
                    }
                }

                // ── Catalog: Available to Download ──
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    HStack {
                        Text("Catalog")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .textCase(.uppercase)
                        Spacer()
                    }

                    ForEach(PresetModel.allCases) { model in
                        ModelCardView(
                            model: model,
                            downloadManager: downloadManager,
                            isActiveModel: vm.selectedModel?.contains(model.filename.replacingOccurrences(of: ".litertlm", with: "")) == true
                        )
                    }
                }

                // ── Import ──
                Button {
                    isImportingModel = true
                } label: {
                    HStack(spacing: 8) {
                        if isCopyingFile {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Importing…")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import from Files")
                        }
                    }
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LamoTheme.Spacing.md)
                }
                .buttonStyle(.glassProminent)
                .foregroundStyle(.white)
                .disabled(isCopyingFile)

                Text(".litertlm, .bin, or .tflite")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))

                // ── Storage ──
                modelsStorageCard

                // ── Model Info ──
                if let info = vm.modelInfo {
                    VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                        Text("Model Info")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .textCase(.uppercase)

                        infoRow(label: "Name", value: info.name)
                        infoRow(label: "File Size", value: info.fileSizeString)
                        infoRow(label: "Speculative Decoding", value: info.hasSpeculativeDecoding ? "YES" : "NO")
                    }
                    .padding(LamoTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Models Hero Card

    private var modelsHeroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
            if let current = vm.selectedModel {
                let name = vm.displayName(for: current)

                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.white.opacity(0.5))
                    Text("ACTIVE")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }

                Text(name)
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Loaded and ready for inference")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))

                if let info = vm.modelInfo {
                    HStack(spacing: LamoTheme.Spacing.lg) {
                        specStat(value: info.fileSizeString, label: "SIZE")
                        specStat(value: info.hasSpeculativeDecoding ? "YES" : "NO", label: "SPEC")
                    }
                }
            } else {
                HStack {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.white.opacity(0.3))
                    Text("NO MODEL")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }

                Text("Select or download a model below")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private func specStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - Model Library Row

    private func modelLibraryRow(model: PresetModel) -> some View {
        let isActive = vm.selectedModel?.contains(model.filename.replacingOccurrences(of: ".litertlm", with: "")) == true

        return Button {
            vm.selectedModel = vm.availableModels.first {
                ($0 as NSString).lastPathComponent == model.filename
            } ?? vm.selectedModel
            vm.loadModelInfo()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(model.parameterCount)
                        Text("·")
                            .foregroundStyle(.white.opacity(0.15))
                        Text(model.fileSizeString)
                        Text("·")
                            .foregroundStyle(.white.opacity(0.15))
                        Text(model.minRAM)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 8, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .rect(cornerRadius: 4))
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.md)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Imported Model Row

    private func importedModelRow(path: String) -> some View {
        Button {
            vm.selectedModel = path
            vm.loadModelInfo()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.displayName(for: path))
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }

                Spacer()

                if vm.selectedModel == path {
                    Text("ACTIVE")
                        .font(.system(size: 8, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .rect(cornerRadius: 4))
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.md)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Models Storage Card

    private var modelsStorageCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("Storage")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            let totalSize = calculateModelsSize()
            let freeSpace = getFreeSpace()

            if totalSize > 0 || freeSpace != nil {
                HStack(spacing: LamoTheme.Spacing.lg) {
                    if totalSize > 0 {
                        specStat(value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), label: "USED")
                    }
                    if let free = freeSpace {
                        specStat(value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file), label: "FREE")
                    }
                }
            }

            Button {
                openModelsFolder()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Open in Files")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 4)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private func storageRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Generation

    private var samplerSection: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                // Temperature
                VStack(alignment: .leading, spacing: 10) {
                    Text("Temperature")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    HStack {
                        Text("Temperature")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.2f", vm.temperature))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Slider(value: $vm.temperature, in: 0.0...2.0, step: 0.05)
                        .tint(.white.opacity(0.5))

                    HStack(spacing: 0) {
                        Text("Focused")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        if vm.temperature >= 0.5 && vm.temperature <= 1.0 {
                            Text("Balanced")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .fontWeight(.medium)
                        } else {
                            Text("Balanced")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer()
                        Text("Creative")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text("0.7 is a good balance.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // Top-K
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top-K")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    HStack {
                        Text("Top-K")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(vm.topK)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Slider(value: Binding(
                        get: { Double(vm.topK) },
                        set: { vm.topK = Int($0) }
                    ), in: 1...100, step: 1)
                        .tint(.white.opacity(0.5))

                    HStack(spacing: 0) {
                        Text("Focused")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        Text("Diverse")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text("Number of top tokens to consider.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // Top-P
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top-P")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    HStack {
                        Text("Top-P")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.2f", vm.topP))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Slider(value: $vm.topP, in: 0.0...1.0, step: 0.05)
                        .tint(.white.opacity(0.5))

                    HStack(spacing: 0) {
                        Text("Narrow")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        Text("Broad")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text("Nucleus sampling probability mass.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // Reset button
                Button {
                    vm.resetSamplerDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LamoTheme.Spacing.md)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Generation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Memory

    private var memorySection: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                // Memory toggle
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    Toggle(isOn: $vm.memoryEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remember Facts")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("AI extracts key facts from conversations")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .accessibilityLabel("Memory")
                    .tint(.white.opacity(0.7))

                    Text("Facts are injected into context for future conversations.")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                if vm.memoryEnabled {
                    // Total facts
                    VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                        HStack {
                            Label("Total Facts", systemImage: "brain")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(MemoryService.shared.totalEntries)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(LamoTheme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                    let facts = MemoryService.shared.allFacts
                    if !facts.isEmpty {
                        // What AI Remembers
                        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                            Text("What AI Remembers")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                                .textCase(.uppercase)

                            ForEach(facts, id: \.id) { fact in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "text.quote")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .frame(width: 16)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fact.text)
                                            .font(.system(.subheadline, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.8))
                                            .textSelection(.enabled)

                                        Text(fact.timestamp, style: .relative)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                    Spacer()
                                    Button {
                                        MemoryService.shared.deleteFact(fact)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                                .padding(.vertical, 4)

                                if fact.id != facts.last?.id {
                                    Divider().background(.white.opacity(0.1))
                                }
                            }
                        }
                        .padding(LamoTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
                    } else {
                        // Empty state
                        VStack(spacing: LamoTheme.Spacing.md) {
                            Image(systemName: "brain")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("No Facts Yet")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("Facts will appear as you chat.")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LamoTheme.Spacing.xl)
                        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
                    }

                    // Clear All Facts
                    Button(role: .destructive) {
                        MemoryService.shared.clearAll()
                    } label: {
                        Label("Clear All Facts", systemImage: "trash")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LamoTheme.Spacing.md)
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                // Compute Backend
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

                // KV-Cache
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

                // Speculative Decoding
                if vm.modelInfo?.hasSpeculativeDecoding == true {
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

                // Vision
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

                // System Prompt
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
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
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
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .disabled(benchmark.isRunning)
                        }
                    }
            } else if benchmark.isRunning {
                // Running — show progress
                ScrollView {
                    VStack(spacing: LamoTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                            Text("Benchmark")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                                .textCase(.uppercase)

                            ProgressView(value: benchmark.progress)
                                .tint(.white.opacity(0.5))

                            Text(benchmarkProgressLabel(benchmark.progress))
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
            } else {
                // No result yet — show start button
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
        }
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
                        .fill(isComplete ? .white.opacity(0.6) : (isCurrent ? .white.opacity(0.15) : Color(.tertiarySystemFill)))
                        .frame(width: 28, height: 28)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    } else if isCurrent {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .controlSize(.mini)
                    } else {
                        Image(systemName: phase.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(phase.rawValue)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(isCurrent ? .white.opacity(0.6) : Color(.tertiaryLabel))
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
