import SwiftData
import SwiftUI

struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @ObservedObject private var memory = MemoryService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showResetAlert = false
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var providerManager = ProviderManager.shared
    // Keychain не публикует изменения — обновляем бейдж вручную при появлении экрана.
    @State private var braveLinked = ProviderManager.shared.braveAPIKey != nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LamoTheme.Spacing.md) {
                    engineCard
                    tuneGrid
                    privacyCard
                    aboutRow
                    footer
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.top, LamoTheme.Spacing.sm)
                .padding(.bottom, LamoTheme.Spacing.xxxl)
            }
            .background(LamoTheme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                }
            }
            .onAppear {
                vm.refreshModels()
                vm.loadModelInfo()
                MemoryService.shared.setModelContext(modelContext)
                braveLinked = ProviderManager.shared.braveAPIKey != nil
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
        case webSearch = "Web Search"
        case tools = "Tools"
    }

    private var providerPickerBinding: Binding<ProviderType> {
        Binding(
            get: { vm.selectedProvider },
            set: { vm.selectedProvider = $0 }
        )
    }

    // MARK: - Engine Card (hero)

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
            if vm.availableProviders.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Engine", selection: providerPickerBinding) {
                        ForEach(vm.availableProviders, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Switching restarts the engine")
                        .font(.caption2)
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                }
                .sensoryFeedback(.selection, trigger: vm.selectedProvider)
            }

            NavigationLink(value: SettingsSection.models) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        statusDot
                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LamoTheme.Colors.textMedium)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LamoTheme.Colors.textGhost)
                    }

                    Text(activeModelName)
                        .font(.title3.bold())
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textLow)
                        .lineLimit(2)

                    if let error = providerManager.engineError?.localizedDescription {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(LamoTheme.Colors.error)
                            .lineLimit(2)
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var activeModelName: String {
        if !vm.isLiteRTSelected { return "Apple Intelligence" }
        if let current = vm.selectedModel { return vm.displayName(for: current) }
        return "No model loaded"
    }

    @ViewBuilder
    private var statusDot: some View {
        if providerManager.isEngineReady {
            Circle()
                .fill(LamoTheme.Colors.accent)
                .frame(width: 8, height: 8)
        } else if providerManager.engineError != nil {
            Circle()
                .fill(LamoTheme.Colors.textMedium)
                .frame(width: 8, height: 8)
        } else {
            ProgressView()
                .controlSize(.mini)
                .tint(LamoTheme.Colors.textMedium)
        }
    }

    private var statusLabel: String {
        if !vm.isLiteRTSelected {
            return String(localized: "System")
        }
        if providerManager.isEngineReady {
            return String(localized: "Ready")
        } else if providerManager.engineError != nil {
            return String(localized: "Attention")
        } else {
            return String(localized: "Loading")
        }
    }

    private var statusSubtitle: String {
        if !vm.isLiteRTSelected {
            if let reason = vm.foundationModelsUnavailableReason {
                return reason
            }
            return String(localized: "Built-in · Private · Nothing to download")
        }
        if vm.selectedModel == nil {
            return String(localized: "Pick a model to start chatting on-device")
        }
        return String(localized: "On-device · Works offline")
    }

    // MARK: - Tune Grid

    private var tuneGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md),
            GridItem(.flexible(), spacing: LamoTheme.Spacing.md)
        ]

        return LazyVGrid(columns: columns, spacing: LamoTheme.Spacing.md) {
            NavigationLink(value: SettingsSection.generation) {
                tile(
                    icon: "slider.horizontal.3",
                    title: String(localized: "Inference"),
                    status: inferenceStatus,
                    detail: inferenceDetail
                )
            }
            .accessibilityLabel("Inference settings, \(inferenceStatus)")

            NavigationLink(value: SettingsSection.memory) {
                tile(
                    icon: "brain.head.profile",
                    title: String(localized: "Memory"),
                    status: memory.isEnabled
                        ? String(localized: "\(memory.totalEntries) facts · On")
                        : String(localized: "Off"),
                    detail: memory.isEnabled
                        ? String(localized: "Remembers across chats")
                        : String(localized: "Turn on to remember")
                )
            }
            .accessibilityLabel("Memory settings")

            NavigationLink(value: SettingsSection.webSearch) {
                tile(
                    icon: "globe",
                    title: String(localized: "Web Search"),
                    status: braveLinked
                        ? String(localized: "Brave linked")
                        : String(localized: "Built-in search"),
                    detail: AppDefaults.webAutoFetch.wrappedValue
                        ? String(localized: "Auto-fetch on")
                        : String(localized: "Auto-fetch off")
                )
            }
            .accessibilityLabel("Web search settings")

            NavigationLink(value: SettingsSection.tools) {
                tile(
                    icon: "wrench.and.screwdriver.fill",
                    title: String(localized: "Tools"),
                    status: toolsStatus,
                    detail: String(localized: "Location · Web · Calendar")
                )
            }
            .accessibilityLabel("Tools settings, \(toolsStatus)")
        }
        .buttonStyle(.plain)
    }

    /// Человеческое резюме семплинга вместо «T:1.0 · K:64».
    private var inferenceStatus: String {
        guard vm.isLiteRTSelected else { return String(localized: "System defaults") }
        let style: String
        switch vm.temperature {
        case ..<0.5: style = String(localized: "Focused")
        case 0.5...1.0: style = isDefaultSampler ? String(localized: "Balanced") : String(localized: "Balanced · Custom")
        default: style = String(localized: "Creative")
        }
        return "\(style) · \(String(format: "%.2f", vm.temperature))"
    }

    private var inferenceDetail: String {
        guard vm.isLiteRTSelected else { return "" }
        let backend = vm.useGPU
            ? String(localized: "GPU")
            : String(localized: "\(vm.cpuThreadCount) CPU")
        let ctx = vm.kvCacheAuto
            ? String(localized: "Auto context")
            : String(localized: "\(vm.maxNumTokens == 0 ? 4096 : vm.maxNumTokens) tokens")
        return "\(backend) · \(ctx)"
    }

    private var isDefaultSampler: Bool {
        vm.temperature == 0.7 && vm.topK == 64 && vm.topP == 0.95
    }

    private var toolsStatus: String {
        let total = ToolInfo.all.count
        let enabled = ToolInfo.all.filter { $0.isEnabled() }.count
        if enabled == total { return String(localized: "All \(total) on") }
        if enabled == 0 { return String(localized: "All off") }
        return String(localized: "\(enabled) of \(total) on")
    }

    /// Стеклянная монохромная плитка — как раньше, без цветных подложек.
    private func tile(icon: String, title: String, status: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(LamoTheme.Colors.textMedium)
                .padding(.bottom, 10)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textHigh)
                .lineLimit(1)

            Text(status)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textLow)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LamoTheme.Spacing.md)
        .frame(minHeight: 128, alignment: .topLeading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    // MARK: - Privacy (честная, а не «всё on-device»)

    private var webToolsActive: Bool {
        AppDefaults.toolWebSearch.wrappedValue
            || AppDefaults.toolFetchURL.wrappedValue
            || AppDefaults.toolWeather.wrappedValue
    }

    private var privacyCard: some View {
        HStack(spacing: LamoTheme.Spacing.sm) {
            Image(systemName: webToolsActive ? "lock.open.fill" : "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(LamoTheme.Colors.textMedium)

            VStack(alignment: .leading, spacing: 1) {
                Text(webToolsActive
                     ? String(localized: "On-device AI · Web only when you ask")
                     : String(localized: "Fully on-device · No network"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                Text(webToolsActive
                     ? String(localized: "Chats and memory never leave the phone")
                     : String(localized: "Chats, models and memory stay on the phone"))
                    .font(.caption2)
                    .foregroundStyle(LamoTheme.Colors.textFaint)
            }
            Spacer()
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm + 2)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - About Links

    private var aboutLinks: some View {
        HStack(spacing: LamoTheme.Spacing.lg) {
            Link(destination: URL(string: "https://ai.google.dev/edge/litert-lm")!) {
                HStack(spacing: 4) {
                    Text("LiteRT-LM")
                        .font(.caption2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(LamoTheme.Colors.textLow)
            }

            Link(destination: URL(string: "https://huggingface.co/litert-community")!) {
                HStack(spacing: 4) {
                    Text("HuggingFace")
                        .font(.caption2)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(LamoTheme.Colors.textLow)
            }

            if vm.availableProviders.contains(.foundationModels) {
                Link(destination: URL(string: "https://developer.apple.com/documentation/FoundationModels")!) {
                    HStack(spacing: 4) {
                        Text("Apple FM")
                            .font(.caption2)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }

            Spacer()

            Button {
                showResetAlert = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text("Reset")
                        .font(.caption2)
                }
                .foregroundStyle(LamoTheme.Colors.textLow)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, LamoTheme.Spacing.sm)
    }

    private var aboutRow: some View { aboutLinks }

    // MARK: - Footer

    private var footer: some View {
        Text("Lamo · v\(appVersionShort)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(LamoTheme.Colors.textGhost)
            .frame(maxWidth: .infinity)
            .padding(.top, LamoTheme.Spacing.md)
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
        case .webSearch:
            WebSearchSettings()
        case .tools:
            ToolsSettingsSection()
        }
    }

    // MARK: - Helpers

    private var appVersionShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
