import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @StateObject private var benchmark = DeviceBenchmark()
    @State private var isImportingModel = false
    @State private var availableModels: [String] = []
    @State private var importError: String?
    @State private var importSuccess = false
    @State private var importedModelName = ""
    @State private var isCopyingFile = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - AI Engine
                providerSection

                // MARK: - Models
                if providerManager.selectedProvider == .litertLM {
                    modelsSection
                }

                // MARK: - Device Performance
                devicePerformanceSection

                // MARK: - Privacy
                privacySection

                // MARK: - About
                aboutSection
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: providerManager.selectedProvider)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                refreshModels()
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
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
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
            .alert("Import Error", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError {
                    Text(error)
                }
            }
            .alert("Model Imported", isPresented: $importSuccess) {
                Button("Use Now") {
                    providerManager.litertLMModelPath = importedModelName
                    refreshModels()
                }
                Button("Later", role: .cancel) {
                    refreshModels()
                }
            } message: {
                Text("\(displayModelName(importedModelName)) is ready to use.")
            }
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        Section {
            Picker(selection: $providerManager.selectedProvider) {
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

            // Engine status
            engineStatusRow
        } header: {
            Text("AI Engine")
        } footer: {
            if providerManager.selectedProvider == .litertLM {
                Text("Runs AI models directly on your device. No internet needed, full privacy.")
            } else {
                Text("Uses Apple's built-in AI. Requires Apple Intelligence enabled in system settings.")
            }
        }
    }

    @ViewBuilder
    private var engineStatusRow: some View {
        if providerManager.selectedProvider == .litertLM {
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
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if providerManager.selectedProvider == .litertLM {
            litertLMOptions
        }
    }

    // MARK: - LiteRT-LM Options

    @ViewBuilder
    private var litertLMOptions: some View {
        if let current = providerManager.litertLMModelPath {
            HStack {
                Label("Active Model", systemImage: "bolt.horizontal.circle.fill")
                    .foregroundStyle(LamoTheme.Colors.success)
                Spacer()
                Text(displayModelName(current))
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }

        if !availableModels.isEmpty {
            Picker(selection: Binding(
                get: { providerManager.litertLMModelPath ?? "" },
                set: { providerManager.litertLMModelPath = $0.isEmpty ? nil : $0 }
            )) {
                Text("Auto-detect").tag("")
                ForEach(availableModels, id: \.self) { model in
                    Text(displayModelName(model)).tag(model)
                }
            } label: {
                Label("Local Model", systemImage: "internaldrive")
            }
        }

        Button {
            isImportingModel = true
        } label: {
            HStack {
                if isCopyingFile {
                    ProgressView()
                        .controlSize(.small)
                    Text("Importing…")
                } else {
                    Label("Import Model", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if !isCopyingFile {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(LamoTheme.Colors.accent)
        .disabled(isCopyingFile)

        Toggle(isOn: $providerManager.litertLMUseGPU) {
            Label("GPU Acceleration", systemImage: "bolt.fill")
        }
        .tint(LamoTheme.Colors.accent)
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        Section {
            ForEach(PresetModel.allCases) { model in
                ModelCardView(model: model, downloadManager: downloadManager)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
        } header: {
            Text("Models")
        } footer: {
            Text("All models run on-device. Your data never leaves your phone.")
        }
    }

    // MARK: - Device Performance Section

    private var devicePerformanceSection: some View {
        Section {
            if let result = benchmark.result {
                // Device info header
                VStack(spacing: 12) {
                    // Device name + tier badge
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

                    // Stats grid
                    HStack(spacing: 0) {
                        statItem("Memory", value: String(format: "%.0f GB", result.ramGB), icon: "memorychip")
                        Spacer()
                        statItem("GPU", value: result.hasGPU ? "Metal" : "None", icon: "gpu")
                        Spacer()
                        statItem("Storage", value: String(format: "%.0f GB", result.storageFreeGB), icon: "internaldrive")
                    }

                    // Compute score
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

                // Recommendations
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

            // Run button
            Button {
                Task { await benchmark.runBenchmark() }
            } label: {
                HStack {
                    if benchmark.isRunning {
                        ProgressView()
                            .controlSize(.small)
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
        } header: {
            Text("Device Performance")
        } footer: {
            Text("Tests your device's ability to run AI models locally.")
        }
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
                    Text("All processing happens on your device. No data is sent anywhere.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func displayModelName(_ path: String) -> String {
        path
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func refreshModels() {
        availableModels = ProviderManager.listModels()
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else { return }

        // Validate file extension
        let ext = url.pathExtension.lowercased()
        guard ext == "litertlm" || ext == "bin" || ext == "tflite" else {
            importError = "Unsupported file type '.\(ext)'. Please select a .litertlm file."
            return
        }

        // Validate file size
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attrs?[.size] as? UInt64 ?? 0
        guard fileSize > 1_000_000 else {  // At least 1MB
            importError = "File is too small (\(formatBytes(fileSize))). It doesn't look like a valid model."
            return
        }

        // Copy in background to avoid UI freeze
        isCopyingFile = true
        Task.detached {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let modelsDir = documents.appendingPathComponent("models")
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

            let fileName = url.lastPathComponent
            let destination = modelsDir.appendingPathComponent(fileName)

            do {
                // Check access to source file (security-scoped)
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }

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
                }
            }
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1_073_741_824 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
    }

    // MARK: - Benchmark UI Helpers

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
