import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var providerManager = ProviderManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isImportingModel = false
    @State private var availableModels: [String] = []

    var body: some View {
        List {
            // MARK: - Provider Selection
            Section {
                Picker("LLM Provider", selection: $providerManager.selectedProvider) {
                    ForEach(ProviderType.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.icon)
                            .tag(provider)
                    }
                }
                .pickerStyle(.menu)

                switch providerManager.selectedProvider {
                case .appleIntelligence:
                    Text("Uses on-device Apple Intelligence. No setup required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                case .litertLM:
                    litertLMSettings
                }
            } header: {
                Text("Provider")
            }

            // MARK: - Model Gallery (only when LiteRT-LM is selected)
            if providerManager.selectedProvider == .litertLM {
                Section {
                    ForEach(PresetModel.allCases) { model in
                        ModelCardView(model: model, downloadManager: downloadManager)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Models")
                        Text("Download a Gemma 4 model to get started. Larger models = better quality, smaller = faster.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Models run entirely on-device. No data leaves your phone.")
                        .font(.footnote)
                }
            }

            // MARK: - About
            Section {
                HStack(spacing: LamoTheme.Spacing.md) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    LabeledContent("Version", value: "1.0")
                }
            } header: {
                Text("About")
            } footer: {
                Text("Lamo uses local device models to process your data privately and securely.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshModels()
        }
    }

    // MARK: - LiteRT-LM Settings

    private var litertLMSettings: some View {
        Group {
            // Active model indicator
            if let current = providerManager.litertLMModelPath {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Active: \(current)")
                        .font(.footnote)
                        .lineLimit(1)
                }
            }

            // Local model picker (from Documents/models/)
            if !availableModels.isEmpty {
                Picker("Local Model", selection: Binding(
                    get: { providerManager.litertLMModelPath ?? "" },
                    set: { providerManager.litertLMModelPath = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Auto-detect").tag("")
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            // Import button
            Button {
                isImportingModel = true
            } label: {
                Label("Import Model Manually", systemImage: "square.and.arrow.down")
            }

            // GPU toggle
            Toggle(isOn: $providerManager.litertLMUseGPU) {
                Label("GPU Acceleration (Metal)", systemImage: "bolt.fill")
            }

            if providerManager.litertLMUseGPU {
                Text("Uses Metal for faster inference. Disable if model doesn't support GPU.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [
                UTType(filenameExtension: "litertlm") ?? .data
            ],
            allowsMultipleSelection: false
        ) { result in
            handleModelImport(result)
        }
    }

    // MARK: - Helpers

    private func refreshModels() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")

        guard FileManager.default.fileExists(atPath: modelsDir.path) else {
            availableModels = []
            return
        }

        if let files = try? FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: nil
        ) {
            availableModels = files
                .filter { $0.pathExtension == "litertlm" }
                .map { $0.lastPathComponent }
        } else {
            availableModels = []
        }
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else { return }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelsDir = documents.appendingPathComponent("models")

        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let destination = modelsDir.appendingPathComponent(url.lastPathComponent)

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            providerManager.litertLMModelPath = destination.lastPathComponent
            refreshModels()
        } catch {
            print("Failed to import model: \(error)")
        }
    }
}
