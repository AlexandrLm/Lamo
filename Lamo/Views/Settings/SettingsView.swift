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
            ScrollView {
                VStack(spacing: LamoTheme.Spacing.lg) {
                    // MARK: - Header
                    headerSection

                    // MARK: - Provider
                    providerSection

                    // MARK: - Models
                    if providerManager.selectedProvider == .litertLM {
                        modelsSection
                    }

                    // MARK: - Privacy
                    privacySection

                    // MARK: - About
                    aboutSection
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.bottom, LamoTheme.Spacing.xxl)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                refreshModels()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: LamoTheme.Spacing.md) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LamoTheme.Colors.accentGradient)
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("Lamo")
                    .font(.title2.bold())

                Text("Local AI Assistant")
                    .font(.subheadline)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LamoTheme.Spacing.xl)
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("PROVIDER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Provider picker
                HStack {
                    Label("Engine", systemImage: "cpu")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $providerManager.selectedProvider) {
                        ForEach(ProviderType.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if providerManager.selectedProvider == .appleIntelligence {
                    Divider().padding(.leading, 44)

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LamoTheme.Colors.success)
                        Text("On-device AI — no setup required")
                            .font(.subheadline)
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if providerManager.selectedProvider == .litertLM {
                    Divider().padding(.leading, 44)
                    litertLMOptions
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
        }
    }

    // MARK: - LiteRT-LM Options

    private var litertLMOptions: some View {
        VStack(spacing: 0) {
            // Active model
            if let current = providerManager.litertLMModelPath {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LamoTheme.Colors.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Model")
                            .font(.caption)
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                        Text(current.replacingOccurrences(of: ".litertlm", with: ""))
                            .font(.subheadline.weight(.medium))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().padding(.leading, 44)
            }

            // Local model picker
            if !availableModels.isEmpty {
                HStack {
                    Label("Local Model", systemImage: "internaldrive")
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { providerManager.litertLMModelPath ?? "" },
                        set: { providerManager.litertLMModelPath = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Auto-detect").tag("")
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().padding(.leading, 44)
            }

            // Import
            Button {
                isImportingModel = true
            } label: {
                HStack(spacing: 12) {
                    Label("Import Model", systemImage: "square.and.arrow.down")
                        .font(.body)
                        .foregroundStyle(LamoTheme.Colors.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().padding(.leading, 44)

            // GPU toggle
            Toggle(isOn: $providerManager.litertLMUseGPU) {
                Label("GPU Acceleration", systemImage: "bolt.fill")
                    .font(.body)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("MODELS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: LamoTheme.Spacing.sm) {
                ForEach(PresetModel.allCases) { model in
                    ModelCardView(model: model, downloadManager: downloadManager)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.caption)
                Text("All models run on-device. Your data never leaves your phone.")
                    .font(.caption)
            }
            .foregroundStyle(LamoTheme.Colors.textTertiary)
            .padding(.horizontal, 4)
            .padding(.top, LamoTheme.Spacing.xs)
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("PRIVACY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fully Local")
                        .font(.subheadline.weight(.semibold))
                    Text("All processing happens on your device")
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Text("ABOUT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack {
                    Text("Version")
                        .font(.body)
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
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
