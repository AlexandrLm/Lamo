import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Models section — active model hero, library, catalog, import.
struct ModelsSettingsSection: View {
    var vm: SettingsViewModel
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isImportingModel = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var importedModelName = ""
    @State private var isCopyingFile = false
    @State private var showError = false
    @State private var showDeleteModelAlert = false
    @State private var modelToDelete: PresetModel?
    @State private var showFilesPicker = false
    // Размер считается в фоне один раз, а не на каждый body (там был дисковый I/O в main).
    @State private var modelsSize: Int64?
    @State private var freeSpace: Int64?

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                heroCard

                if vm.isLiteRTSelected {
                    librarySection
                    catalogSection
                    addSection
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshStorage() }
        .onChange(of: vm.availableModels.count) { _, _ in
            Task { await refreshStorage() }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in handleModelImport(result) }
        .overlay {
            if isCopyingFile {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text("Importing model…")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(LamoTheme.Colors.textMedium)
                    }
                    .padding(28).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert("Import Error", isPresented: $showError) {
            Button("OK") { importError = nil }
        } message: { if let e = importError { Text(e) } }
        .alert("Model Imported", isPresented: $importSuccess) {
            Button("Use Now") { vm.selectedModel = importedModelName; vm.refreshModels(); vm.loadModelInfo() }
            Button("Later", role: .cancel) { vm.refreshModels() }
        } message: { Text("\(vm.displayName(for: importedModelName)) is ready to use.") }
        .alert("Delete Model?", isPresented: $showDeleteModelAlert) {
            Button("Delete", role: .destructive) {
                if let m = modelToDelete { downloadManager.deleteModel(m) }
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) { modelToDelete = nil }
        } message: {
            if let m = modelToDelete { Text("Remove \(m.displayName) from your device?") }
        }
        .sheet(isPresented: $showFilesPicker) { FilesFolderPicker() }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroCard: some View {
        if !vm.isLiteRTSelected {
            fmHeroCard
        } else {
            litertHeroCard
        }
    }

    private var fmHeroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack(spacing: LamoTheme.Spacing.sm) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 12))
                    .foregroundStyle(LamoTheme.Colors.accent)
                Text("ON-DEVICE")
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                Spacer()
            }

            Text("Apple Intelligence")
                .font(.system(.title3, design: .monospaced).bold())
                .foregroundStyle(LamoTheme.Colors.textHigh)

            HStack(spacing: LamoTheme.Spacing.sm) {
                specChip(icon: "lock.shield.fill", value: String(localized: "Private"))
                specChip(icon: "bolt.fill", value: String(localized: "On-Device"))
                specChip(icon: "sparkles", value: "iOS 26+")
            }

            Text("Built-in system language model · No download needed · A17 Pro / M1+ · Image input needs iOS 27")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    @ViewBuilder
    private var litertHeroCard: some View {
        let current = vm.selectedModel
        let info = vm.modelInfo
        Group {
            if let current, let info {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                HStack(spacing: LamoTheme.Spacing.sm) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(LamoTheme.Colors.accent)
                    Text("ACTIVE")
                        .font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(LamoTheme.Colors.accent)
                    Spacer()
                }

                Text(vm.displayName(for: current))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .lineLimit(1).truncationMode(.middle)

                // Spec chips
                HStack(spacing: LamoTheme.Spacing.sm) {
                    specChip(icon: "internaldrive", value: info.fileSizeString)
                    specChip(icon: "bolt.speedometer", value: info.hasSpeculativeDecoding ? "SpecDec" : "Base")
                    specChip(icon: "arrow.triangle.branch", value: activeCoresLabel)
                }

                Text("On-device inference · No network required")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                }
            } else {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                HStack(spacing: LamoTheme.Spacing.sm) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 9)).foregroundStyle(LamoTheme.Colors.textFaint)
                    Text("NO MODEL").font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                    Spacer()
                }
                Text("Download or import a model to get started")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    /// Было `static let` — застывало на значениях с первого запуска и врало
    /// после переключения GPU/CPU. Теперь живое вычисленное свойство.
    private var activeCoresLabel: String {
        guard AppDefaults.useGPU.wrappedValue else { return "\(AppDefaults.cpuThreadCount.wrappedValue) CPU" }
        if let dev = MTLCreateSystemDefaultDevice() {
            if dev.supportsFamily(.apple9) { return "6 GPU" }
            if dev.supportsFamily(.apple8) { return "5 GPU" }
            return "GPU"
        }
        return "GPU"
    }

    private func specChip(icon: String, value: String) -> some View {
        Chip(text: value, icon: icon)
    }

    // MARK: - Library

    private var librarySection: some View {
        let downloadedPresets = PresetModel.allCases.filter { $0.isDownloaded }
        let localModels = vm.availableModels.filter { path in
            !PresetModel.allCases.contains { $0.filename == (path as NSString).lastPathComponent }
        }
        let total = downloadedPresets.count + localModels.count

        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            if total > 0 {
                sectionLabel(String(localized: "Library"), count: "\(total)")
            }

            if downloadedPresets.isEmpty && localModels.isEmpty {
                Text("No models yet — download or import below")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
            }

            ForEach(downloadedPresets) { model in libraryRow(model: model) }
            ForEach(localModels, id: \.self) { path in importedRow(path: path) }
        }
    }

    private func libraryRow(model: PresetModel) -> some View {
        let isActive = vm.selectedModel.map { ($0 as NSString).lastPathComponent == model.filename } ?? false
        let info = isActive ? vm.modelInfo : nil

        var meta: String {
            var parts = [model.parameterCount, model.actualFileSizeString]
            if info?.hasSpeculativeDecoding == true { parts.append("Draft") }
            return parts.joined(separator: " · ")
        }

        return modelRow(
            icon: model.systemImage,
            title: model.displayName,
            meta: meta,
            isActive: isActive,
            canDelete: true,
            onSelect: {
                vm.selectedModel = vm.availableModels.first { ($0 as NSString).lastPathComponent == model.filename } ?? model.localPath
                vm.loadModelInfo(); vm.refreshModels()
            },
            onDelete: { modelToDelete = model; showDeleteModelAlert = true }
        )
    }

    private func importedRow(path: String) -> some View {
        let isActive = vm.selectedModel == path
        return modelRow(
            icon: "doc.zipper",
            title: vm.displayName(for: path),
            meta: (path as NSString).lastPathComponent,
            isActive: isActive,
            canDelete: !isActive,
            onSelect: { vm.selectedModel = path; vm.loadModelInfo(); vm.refreshModels() },
            onDelete: {
                try? FileManager.default.removeItem(atPath: path)
                vm.refreshModels(); vm.loadModelInfo()
            }
        )
    }

    /// Единая строка библиотеки — раньше libraryRow/importedRow дублировали ~50 строк вёрстки.
    private func modelRow(
        icon: String,
        title: String,
        meta: String,
        isActive: Bool,
        canDelete: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if isActive {
                    Circle()
                        .stroke(LamoTheme.Colors.accent, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? LamoTheme.Colors.accent : LamoTheme.Colors.textLow)
            }
            .frame(width: 34, height: 34)

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LamoTheme.Colors.textHigh)
                        if isActive { Badge(text: "ACTIVE") }
                    }
                    Text(meta)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                        .lineLimit(1)
                }
                Spacer()
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(canDelete ? LamoTheme.Colors.textFaint : LamoTheme.Colors.textGhost)
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, LamoTheme.Spacing.md).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        let availableToDownload = PresetModel.allCases.filter { !$0.isDownloaded }

        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            if !availableToDownload.isEmpty {
                sectionLabel(String(localized: "Catalog"), count: nil)

                ForEach(availableToDownload) { model in
                    ModelCardView(
                        model: model,
                        downloadManager: downloadManager,
                        isActiveModel: vm.selectedModel.map { ($0 as NSString).lastPathComponent == model.filename } ?? false,
                        onSelect: { vm.selectedModel = model.localPath; vm.loadModelInfo() }
                    )
                }
            }
        }
    }

    // MARK: - Add

    private var addSection: some View {
        VStack(spacing: LamoTheme.Spacing.sm) {
            Button { isImportingModel = true } label: {
                Label("Import .litertlm File", systemImage: "square.and.arrow.down")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))

            Button { openModelsFolder() } label: {
                Label("Open Models Folder", systemImage: "folder")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))

            storageCard
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            sectionLabel(String(localized: "Storage"), count: nil)
            HStack {
                infoRow(label: String(localized: "Models"), value: modelsSize.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "…")
                Spacer()
                infoRow(label: String(localized: "Free"), value: freeSpace.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "—")
            }
            if let used = modelsSize, let free = freeSpace, free > 0 {
                MeterBar(value: Double(used) / Double(used + free))
                    .padding(.top, 4)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(LamoTheme.Colors.textMedium)
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(LamoTheme.Colors.textFaint).textCase(.uppercase)
        }
    }

    // MARK: - Import

    private func handleModelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Быстрый отказ с понятной ошибкой вместо копирования мусора.
            guard url.pathExtension.lowercased() == "litertlm" else {
                importError = String(localized: "That file isn't a .litertlm model. Pick a file ending in .litertlm.")
                showError = true
                return
            }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            isCopyingFile = true
            let dest = ProviderManager.modelsDirectory.appendingPathComponent(url.lastPathComponent)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.copyItem(at: url, to: dest)
                    DispatchQueue.main.async {
                        isCopyingFile = false; importedModelName = dest.path
                        vm.refreshModels(); vm.loadModelInfo(); importSuccess = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        isCopyingFile = false; importError = error.localizedDescription; showError = true
                    }
                }
            }
        case .failure(let error):
            importError = error.localizedDescription; showError = true
        }
    }

    private func openModelsFolder() { showFilesPicker = true }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, count: String?) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .textCase(.uppercase)
            if let count {
                Text(count)
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
            }
            Spacer()
        }
    }

    private func refreshStorage() async {
        let dir = ProviderManager.modelsDirectory
        let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64?) in
            var total: Int64 = 0
            if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for url in contents {
                    if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
                       let size = attrs.fileSize { total += Int64(size) }
                }
            }
            let free: Int64? = {
                guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                      let f = attrs[.systemFreeSize] as? Int64 else { return nil }
                return f
            }()
            return (total, free)
        }.value
        await MainActor.run {
            modelsSize = sizes.0
            freeSpace = sizes.1
        }
    }
}

// MARK: - Files Folder Picker

struct FilesFolderPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let dir = ProviderManager.modelsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.directoryURL = dir
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
