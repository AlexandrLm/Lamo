import SwiftUI

/// Memory settings section — toggle, fact list, clear all.
/// Extracted from SettingsView for maintainability.
struct MemorySettingsSection: View {
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject private var memory = MemoryService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                toggleCard
                if vm.memoryEnabled {
                    totalFactsCard
                    factsListCard
                    clearButton
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            Toggle(isOn: $vm.memoryEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember Facts")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("AI extracts key facts from conversations")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .accessibilityLabel("Memory")
            .tint(.white.opacity(0.7))

            Text("Facts are injected into context for future conversations.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var totalFactsCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack {
                Label("Total Facts", systemImage: "brain")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(memory.totalEntries)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var factsListCard: some View {
        let facts = memory.allFacts

        return Group {
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    Text("What AI Remembers")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .textCase(.uppercase)

                    ForEach(facts, id: \.id) { fact in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "text.quote")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 16)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.text)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .textSelection(.enabled)

                                Text(fact.timestamp, style: .relative)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            Spacer()
                            Button {
                                memory.deleteFact(fact)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }
                        .padding(.vertical, 4)

                        if fact.id != facts.last?.id {
                            Divider().background(.white.opacity(0.1))
                        }
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            } else {
                VStack(spacing: LamoTheme.Spacing.md) {
                    Image(systemName: "brain")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No Facts Yet")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Facts will appear as you chat.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.xl)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            memory.clearAll()
        } label: {
            Label("Clear All Facts", systemImage: "trash")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }
}
