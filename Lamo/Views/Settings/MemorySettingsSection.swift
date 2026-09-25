import SwiftUI

/// Memory / Context screen — toggle, fact summary, fact list with rich info.
struct MemorySettingsSection: View {
    @Bindable var vm: SettingsViewModel
    @ObservedObject private var memory = MemoryService.shared
    @State private var showClearConfirmation = false
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                heroCard

                if vm.memoryEnabled {
                    factsCard
                    clearButton
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Clear all facts?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) { memory.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(memory.totalEntries) remembered facts. AI will start fresh.")
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
            // Toggle row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 13))
                            .foregroundStyle(vm.memoryEnabled ? LamoTheme.Colors.accent : LamoTheme.Colors.textFaint)
                        Text("Memory")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(LamoTheme.Colors.textHigh)
                    }
                    Text("AI remembers key facts across chats")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
                Spacer()
                Toggle("", isOn: $vm.memoryEnabled)
                    .labelsHidden()
                    .tint(LamoTheme.Colors.accent)
            }

            // Stats row when enabled
            if vm.memoryEnabled {
                HStack(spacing: LamoTheme.Spacing.lg) {
                    statBadge(icon: "text.quote", value: "\(memory.totalEntries)", label: String(localized: "FACTS"))
                    statBadge(icon: "clock.arrow.2.circlepath", value: lastUsed, label: String(localized: "LAST"))
                    statBadge(icon: "character.cursor.ibeam", value: totalChars, label: String(localized: "CHARS"))
                    Spacer()
                }
            }

            Text(vm.memoryEnabled
                 ? "Facts are injected into context so AI can reference them in future conversations."
                 : "Enable to let AI extract and remember important facts from your conversations.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .animation(.easeInOut(duration: 0.2), value: vm.memoryEnabled)
    }

    // MARK: - Facts

    private var factsCard: some View {
        let facts = memory.allFacts
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = query.isEmpty
            ? facts
            : facts.filter { $0.text.localizedCaseInsensitiveContains(query) }

        return Group {
            if facts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel(
                        String(localized: "Remembered"),
                        icon: "brain",
                        count: query.isEmpty ? "\(facts.count)" : "\(visible.count)/\(facts.count)"
                    )

                    if facts.count > 3 {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundStyle(LamoTheme.Colors.textFaint)
                            TextField("Filter facts…", text: $searchText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(LamoTheme.Colors.textHigh)
                                .autocorrectionDisabled()
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(LamoTheme.Colors.textFaint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(LamoTheme.Colors.fillSubtle, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, LamoTheme.Spacing.sm)
                    }

                    if visible.isEmpty {
                        Text("No facts match this filter")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(LamoTheme.Colors.textFaint)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, LamoTheme.Spacing.lg)
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { i, fact in
                            if i > 0 { thinDivider }
                            factRow(fact)
                        }
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
        }
    }

    private func factRow(_ fact: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Accent dot
            Circle()
                .fill(LamoTheme.Colors.accent.opacity(0.5))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(fact.text)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(fact.timestamp, style: .relative)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                    if fact.usageCount > 0 {
                        Text("·").foregroundStyle(LamoTheme.Colors.textGhost)
                        Text("Used \(fact.usageCount)×")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(LamoTheme.Colors.accent.opacity(0.4))
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    memory.deleteFact(fact)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete fact")
            .padding(.top, 2)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LamoTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(LamoTheme.Colors.accent.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 26))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
            }

            Text("No Facts Yet")
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textMedium)

            Text("Facts appear automatically as you chat.\nThe AI extracts key details and remembers them.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LamoTheme.Spacing.xxl)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Clear

    private var clearButton: some View {
        Button {
            showClearConfirmation = true
        } label: {
            Label("Clear All Facts", systemImage: "trash")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textLow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .disabled(memory.totalEntries == 0)
        .opacity(memory.totalEntries == 0 ? 0.4 : 1)
    }

    // MARK: - Computed

    private var lastUsed: String {
        guard let latest = memory.allFacts.map(\.timestamp).max() else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: latest, relativeTo: .now)
    }

    private var totalChars: String {
        let count = memory.allFacts.map(\.text.count).reduce(0, +)
        if count >= 1000 { return "\(count / 1000)k" }
        return "\(count)"
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, icon: String, count: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LamoTheme.Colors.accent)
            Text(text)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .textCase(.uppercase)
            Text(count)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
            Spacer()
        }
        .padding(.bottom, LamoTheme.Spacing.sm)
    }

    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 7))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
                Text(value)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
            }
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .textCase(.uppercase)
        }
    }

    private var thinDivider: some View {
        ThinDivider()
    }
}
