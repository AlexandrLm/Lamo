import SwiftUI
import UniformTypeIdentifiers

/// Models section — library, catalog, import, storage.
/// Extracted from SettingsView for maintainability.
struct ModelsSettingsSection: View {
    @ObservedObject var vm: SettingsViewModel
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

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.lg) {
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
        .alert("Delete Model?", isPresented: $showDeleteModelAlert) {
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    downloadManager.deleteModel(model)
                }
                modelToDelete = nil
            }
            Button("Cancel", role: .cancel) { modelToDelete = nil }
        } message: {
            if let model = modelToDelete {
                Text("Remove \(model.displayName) from your device?")
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
            if let current = vm.selectedModel {
                HStack {
                    Image(systemName: "bolt.fill").foregroundStyle(.white.opacity(0.5))
                    Text("ACTIVE").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                Text(vm.displayName(for: current))
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                if let info = vm.modelInfo {
                    HStack(spacing: LamoTheme.Spacing.lg) {
                        specStat(value: info.fileSizeString, label: "SIZE")
                        specStat(value: info.hasSpeculativeDecoding ? "YES" : "NO", label: "SPEC")
                    }
                }
            } else {
                HStack {
                    Image(systemName: "minus.circle").foregroundStyle(.white.opacity(0.3))
                    Text("NO MODEL").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                    Spacer()
                }
                Text("Download or import a model below")
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
            Text(value).font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(label).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - Library (downloaded + imported models)

    private var librarySection: some View {
        let downloadedPresets = PresetModel.allCases.filter { $0.isDownloaded }
        let localModels = vm.availableModels.filter { path in
            !PresetModel.allCases.contains { $0.filename == (path as NSString).lastPathComponent }
        }

        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack {
                Text("Library").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3)).textCase(.uppercase)
                Spacer()
                Text("\(downloadedPresets.count + localModels.count)").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }

            if downloadedPresets.isEmpty && localModels.isEmpty {
                Text("No models yet — download or import below")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.vertical, 8)
            }

            ForEach(downloadedPresets) { model in
                libraryRow(model: model)
            }

            ForEach(localModels, id: \.self) { path in
                importedRow(path: path)
            }
        }
    }

    private func libraryRow(model: PresetModel) -> some View {
        let isActive = vm.selectedModel.map { ($0 as NSString).lastPathComponent == model.filename } ?? false
        let isPartial = model.isPartialDownload

        return HStack(spacing: 12) {
            Button {
                vm.selectedModel = vm.availableModels.first {
                    ($0 as NSString).lastPathComponent == model.filename
                } ?? model.localPath
                vm.loadModelInfo()
                vm.refreshModels()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.systemImage)
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName).font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(model.parameterCount)
                            Text("·").foregroundStyle(.white.opacity(0.15))
                            Text(model.actualFileSizeString)
                            if isPartial {
                                Text("·").foregroundStyle(.white.opacity(0.15))
                                Text("INCOMPLETE")
                                    .foregroundStyle(.orange.opacity(0.7))
                            }
                        }
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                    if isActive {
                        Text("ACTIVE").font(.system(size: 8, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                            .glassEffect(.regular, in: .rect(cornerRadius: 4))
                    }
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                modelToDelete = model
                showDeleteModelAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, LamoTheme.Spacing.md).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    private func importedRow(path: String) -> some View {
        let isActive = vm.selectedModel == path

        return HStack(spacing: 12) {
            Button {
                vm.selectedModel = path
                vm.loadModelInfo()
                vm.refreshModels()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.displayName(for: path))
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white).lineLimit(1)
                        Text((path as NSString).lastPathComponent)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                    }
                    Spacer()
                    if isActive {
                        Text("ACTIVE").font(.system(size: 8, design: .monospaced).weight(.medium))
                            .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                            .glassEffect(.regular, in: .rect(cornerRadius: 4))
                    }
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                guard !isActive else { return }
                try? FileManager.default.removeItem(atPath: path)
                vm.refreshModels()
                vm.loadModelInfo()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(isActive ? 0.05 : 0.2))
            }
            .buttonStyle(.plain)
            .disabled(isActive)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, LamoTheme.Spacing.md).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    // MARK: - Catalog (models available to download)

    private var catalogSection: some View {
        let availableToDownload = PresetModel.allCases.filter { !$0.isDownloaded }

        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            if !availableToDownload.isEmpty {
                HStack {
                    Text("Catalog").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3)).textCase(.uppercase)
                    Spacer()
                }

                ForEach(availableToDownload) { model in
                    ModelCardView(
                        model: model,
                        downloadManager: downloadManager,
                        isActiveModel: vm.selectedModel.map { ($0 as NSString).lastPathComponent == model.filename } ?? false,
                        onSelect: {
                            vm.selectedModel = model.localPath
                            vm.loadModelInfo()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Add (import + open in files + storage)

    private var addSection: some View {
        VStack(spacing: LamoTheme.Spacing.md) {
            HStack(spacing: LamoTheme.Spacing.md) {
                Button {
                    isImportingModel = true
                } label: {
                    HStack(spacing: 6) {
                        if isCopyingFile {
                            ProgressView().controlSize(.mini).tint(.white)
                            Text("Importing…")
                        } else {
                            Image(systemName: "plus")
                            Text("Import")
                        }
                    }
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isCopyingFile)

                Button {
                    openModelsFolder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Open in Files")
                    }
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
            }

            storageCard
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("Storage").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3)).textCase(.uppercase)
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
            if let info = vm.modelInfo {
                Divider().background(.white.opacity(0.06))
                infoRow(label: "Name", value: info.name)
                infoRow(label: "Speculative", value: info.hasSpeculativeDecoding ? "YES" : "NO")
            }
            Divider().background(.white.opacity(0.06))
            infoRow(label: "Location", value: "Files → On My iPhone → Lamo → models")
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
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
                .lineLimit(1)
                .truncationMode(.middle)
        }
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

    // MARK: - Open in Files

    private func openModelsFolder() {
        let modelsDir = ProviderManager.modelsDirectory
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        UIApplication.shared.open(modelsDir)
    }

    // MARK: - Storage Helpers

    private func calculateModelsSize() -> Int64 {
        let modelsDir = ProviderManager.modelsDirectory
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
}
