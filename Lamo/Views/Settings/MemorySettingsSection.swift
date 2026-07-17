import SwiftUI

/// Memory / Context screen — toggle, fact summary, fact list with rich info.
struct MemorySettingsSection: View {
    @Bindable var vm: SettingsViewModel
    @ObservedObject private var memory = MemoryService.shared
    @State private var showClearConfirmation = false

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
                            .foregroundStyle(vm.memoryEnabled ? LamoTheme.Colors.accent : .white.opacity(0.3))
                        Text("Memory")
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    Text("AI remembers key facts across chats")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                Toggle("", isOn: $vm.memoryEnabled)
                    .labelsHidden()
                    .tint(LamoTheme.Colors.accent)
            }

            // Stats row when enabled
            if vm.memoryEnabled {
                HStack(spacing: LamoTheme.Spacing.lg) {
                    statBadge(icon: "text.quote", value: "\(memory.totalEntries)", label: "FACTS")
                    statBadge(icon: "clock.arrow.2.circlepath", value: lastUsed, label: "LAST")
                    statBadge(icon: "character.cursor.ibeam", value: totalChars, label: "CHARS")
                    Spacer()
                }
            }

            Text(vm.memoryEnabled
                 ? "Facts are injected into context so AI can reference them in future conversations."
                 : "Enable to let AI extract and remember important facts from your conversations.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.22))
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

        return Group {
            if facts.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Remembered", icon: "brain", count: "\(facts.count)")

                    ForEach(Array(facts.enumerated()), id: \.element.id) { i, fact in
                        if i > 0 { thinDivider }
                        factRow(fact)
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
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(fact.timestamp, style: .relative)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    if fact.usageCount > 0 {
                        Text("·").foregroundStyle(.white.opacity(0.15))
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
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .buttonStyle(.plain)
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
                .foregroundStyle(.white.opacity(0.6))

            Text("Facts appear automatically as you chat.\nThe AI extracts key details and remembers them.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
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
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .disabled(memory.totalEntries == 0)
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
                .foregroundStyle(.white.opacity(0.25))
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
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .textCase(.uppercase)
        }
    }

    private var thinDivider: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
    }
}
