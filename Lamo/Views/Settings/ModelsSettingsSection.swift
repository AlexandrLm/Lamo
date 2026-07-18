import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Models section — active model hero, library, catalog, import.
struct ModelsSettingsSection: View {
    var vm: SettingsViewModel
    @ObservedObject var downloadManager = DownloadManager.shared
    @Environment(\.modelContext) private var modelContext
    @State private var isImportingModel = false
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var importedModelName = ""
    @State private var isCopyingFile = false
    @State private var showError = false
    @State private var showDeleteModelAlert = false
    @State private var modelToDelete: PresetModel?
    @State private var showFilesPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                heroCard
                librarySection
                catalogSection
                addSection
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
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
                            .foregroundStyle(.white.opacity(0.7))
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            if let current = vm.selectedModel, let info = vm.modelInfo {
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
                    .foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)

                // Spec chips
                HStack(spacing: LamoTheme.Spacing.sm) {
                    specChip(icon: "internaldrive", value: info.fileSizeString)
                    specChip(icon: "bolt.speedometer", value: info.hasSpeculativeDecoding ? "SpecDec" : "Base")
                    if let cores = activeCores { specChip(icon: "arrow.triangle.branch", value: cores) }
                }

                Text("On-device inference · No network required")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            } else {
                HStack(spacing: LamoTheme.Spacing.sm) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
                    Text("NO MODEL").font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                Text("Download or import a model to get started")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var activeCores: String? {
        guard vm.useGPU else { return "\(vm.cpuThreadCount) CPU" }
        if let dev = MTLCreateSystemDefaultDevice() {
            if dev.supportsFamily(.apple9) { return "6 GPU" }
            if dev.supportsFamily(.apple8) { return "5 GPU" }
            return "GPU"
        }
        return "GPU"
    }

    private func specChip(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
            Text(value)
                .font(.system(size: 10, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                sectionLabel("Library", count: "\(total)")
            }

            if downloadedPresets.isEmpty && localModels.isEmpty {
                Text("No models yet — download or import below")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            ForEach(downloadedPresets) { model in libraryRow(model: model) }
            ForEach(localModels, id: \.self) { path in importedRow(path: path) }
        }
    }

    private func libraryRow(model: PresetModel) -> some View {
        let isActive = vm.selectedModel.map { ($0 as NSString).lastPathComponent == model.filename } ?? false
        let info = isActive ? vm.modelInfo : nil

        return HStack(spacing: 10) {
            // Model icon with accent ring if active
            ZStack {
                if isActive {
                    Circle()
                        .stroke(LamoTheme.Colors.accent, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
                Image(systemName: model.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? LamoTheme.Colors.accent : .white.opacity(0.45))
            }
            .frame(width: 34, height: 34)

            Button {
                vm.selectedModel = vm.availableModels.first { ($0 as NSString).lastPathComponent == model.filename } ?? model.localPath
                vm.loadModelInfo(); vm.refreshModels()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 7, design: .monospaced).weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(LamoTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 6) {
                        Text(model.parameterCount).foregroundStyle(.white.opacity(0.5))
                        Text("·").foregroundStyle(.white.opacity(0.15))
                        Text(model.actualFileSizeString).foregroundStyle(.white.opacity(0.4))
                        if let info, info.hasSpeculativeDecoding {
                            Text("·").foregroundStyle(.white.opacity(0.15))
                            Text("Draft").foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                }
                Spacer()
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                modelToDelete = model; showDeleteModelAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.15))
            }
            .buttonStyle(.plain).padding(.trailing, 2)
        }
        .padding(.horizontal, LamoTheme.Spacing.md).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    private func importedRow(path: String) -> some View {
        let isActive = vm.selectedModel == path

        return HStack(spacing: 10) {
            ZStack {
                if isActive {
                    Circle()
                        .stroke(LamoTheme.Colors.accent, lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }
                Image(systemName: "doc.zipper")
                    .font(.system(size: 15))
                    .foregroundStyle(isActive ? LamoTheme.Colors.accent : .white.opacity(0.45))
            }
            .frame(width: 34, height: 34)

            Button {
                vm.selectedModel = path; vm.loadModelInfo(); vm.refreshModels()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vm.displayName(for: path))
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 7, design: .monospaced).weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(LamoTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text((path as NSString).lastPathComponent)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                guard !isActive else { return }
                try? FileManager.default.removeItem(atPath: path)
                vm.refreshModels(); vm.loadModelInfo()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(isActive ? 0.05 : 0.15))
            }
            .buttonStyle(.plain).disabled(isActive).padding(.trailing, 2)
        }
        .padding(.horizontal, LamoTheme.Spacing.md).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        let availableToDownload = PresetModel.allCases.filter { !$0.isDownloaded }

        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            if !availableToDownload.isEmpty {
                sectionLabel("Catalog", count: nil)

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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))

            Button { openModelsFolder() } label: {
                Label("Open Models Folder", systemImage: "folder")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))

            storageCard
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            sectionLabel("Storage", count: nil)
            HStack {
                infoRow(label: "Models", value: ByteCountFormatter.string(fromByteCount: calculateModelsSize(), countStyle: .file))
                Spacer()
                infoRow(label: "Free", value: {
                    if let free = getFreeSpace() {
                        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                    }
                    return "—"
                }())
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.25)).textCase(.uppercase)
        }
    }

    // MARK: - Import

    private func handleModelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
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
                .foregroundStyle(.white.opacity(0.25))
                .textCase(.uppercase)
            if let count {
                Text(count)
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
            }
            Spacer()
        }
    }

    private func calculateModelsSize() -> Int64 {
        var total: Int64 = 0
        let dir = ProviderManager.modelsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for url in contents {
                if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attrs.fileSize { total += Int64(size) }
            }
        }
        return total
    }

    private func getFreeSpace() -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return nil }
        return free
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
