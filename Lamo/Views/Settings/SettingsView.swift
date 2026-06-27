import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var providerManager = ProviderManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isImportingModel = false
    @State private var availableModels: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                        Label("On-device AI — no setup required", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(LamoTheme.Colors.success)

                    case .litertLM:
                        litertLMSettings
                    }
                } header: {
                    Label("Provider", systemImage: "cpu")
                }

                // MARK: - Model Gallery
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
                            Label("Available Models", systemImage: "arrow.down.circle")
                            Text("Download a Gemma 4 model to get started")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Label("All models run on-device. Your data never leaves your phone.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                    }
                }

                // MARK: - Privacy
                Section {
                    Label("All processing happens locally on your device", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                } header: {
                    Label("Privacy", systemImage: "hand.raised")
                }

                // MARK: - About
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(LamoTheme.Colors.accent)
                            .font(.title3)
                        LabeledContent("Version", value: "1.0")
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshModels()
            }
        }
    }

    // MARK: - LiteRT-LM Settings

    private var litertLMSettings: some View {
        Group {
            // Active model indicator
            if let current = providerManager.litertLMModelPath {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LamoTheme.Colors.success)
                    Text("Active: \(current)")
                        .font(.footnote)
                        .lineLimit(1)
                }
            }

            // Local model picker
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
                Label("Import Model", systemImage: "square.and.arrow.down")
            }

            // GPU toggle
            Toggle(isOn: $providerManager.litertLMUseGPU) {
                Label("GPU Acceleration", systemImage: "bolt.fill")
            }

            if providerManager.litertLMUseGPU {
                Text("Uses Metal for faster inference")
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

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            providerManager.litertLMModelPath = url.lastPathComponent
            refreshModels()
        } catch {
            print("Import failed: \(error)")
        }
    }
}
