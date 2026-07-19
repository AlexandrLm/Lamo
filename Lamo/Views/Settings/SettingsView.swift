import SwiftData
import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var memory = MemoryService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var providerManager = ProviderManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LamoTheme.Spacing.lg) {
                    heroCard
                        .padding(.top, LamoTheme.Spacing.sm)
                    actionGrid
                    privacyRow
                    aboutLinks
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

    // MARK: - Sections

    enum SettingsSection: String, CaseIterable, Hashable {
        case models = "Models"
        case generation = "Inference"
        case memory = "Memory"
        case tools = "Tools"
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        NavigationLink(value: SettingsSection.models) {
            VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                HStack(spacing: LamoTheme.Spacing.sm) {
                    statusDot
                    Text(statusLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.2))
                }

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

                Text("On-device · No internet")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(LamoTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        } else if providerManager.engineError != nil {
            return "Error"
        } else {
            return "Loading"
        }
    }


    // MARK: - Action Grid

    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md),
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md)
        ]

        return LazyVGrid(columns: columns, spacing: LamoTheme.Spacing.md) {
            NavigationLink(value: SettingsSection.generation) {
                gridCard(
                    icon: "sparkles",
                    title: "Inference",
                    subtitle: gridSubtitle_generation,
                    subtitle2: gridSubtitle_generation2
                )
            }

            NavigationLink(value: SettingsSection.memory) {
                gridCard(icon: "brain", title: "Memory", subtitle: "\(memory.totalEntries) facts")
            }

            NavigationLink {
                WebSearchSettings()
            } label: {
                gridCard(
                    icon: "globe",
                    title: "Web Search",
                    subtitle: ProviderManager.shared.braveAPIKey != nil ? "Brave + SearXNG" : "SearXNG"
                )
            }

            NavigationLink(value: SettingsSection.tools) {
                gridCard(icon: "wrench.and.screwdriver.fill", title: "Tools", subtitle: toolsSubtitle)
            }
        }
    }

    private var gridSubtitle_generation: String {
        "T:\(String(format: "%.1f", vm.temperature)) · K:\(vm.topK) · P:\(String(format: "%.2f", vm.topP))"
    }

    private var gridSubtitle_generation2: String {
        let backend = vm.useGPU ? "GPU" : "CPU×\(vm.cpuThreadCount)"
        let kv = vm.kvCacheAuto ? "Auto ctx" : "\(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens) ctx"
        return "\(backend) · \(kv)"
    }

    private var toolsSubtitle: String {
        let total = ToolInfo.all.count
        let enabled = ToolInfo.all.filter { $0.isEnabled() }.count
        return "\(enabled)/\(total) enabled"
    }

    private func gridCard(icon: String, title: String, subtitle: String, subtitle2: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.xs) {
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

            if let subtitle2 {
                Text(subtitle2)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
            ModelsSettingsSection(vm: vm)
        case .generation:
            GenerationComputeSection(vm: vm)
        case .memory:
            MemorySettingsSection(vm: vm)
        case .tools:
            ToolsSettingsSection()
        }
    }

    // MARK: - Helpers

    private var appVersionShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

}
