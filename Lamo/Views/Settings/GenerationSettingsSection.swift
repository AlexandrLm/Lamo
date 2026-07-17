import SwiftUI

/// Generation settings section — temperature, top-k, top-p, reset.
/// Extracted from SettingsView for maintainability.
struct GenerationSettingsSection: View {
    @Bindable var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                temperatureCard
                topKCard
                topPCard
                resetButton
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Generation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperature")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            HStack {
                Text("Temperature")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.2f", vm.temperature))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Slider(value: $vm.temperature, in: 0.0...2.0, step: 0.05)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                Text("Focused")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                if vm.temperature >= 0.5 && vm.temperature <= 1.0 {
                    Text("Balanced")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .fontWeight(.medium)
                } else {
                    Text("Balanced")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                Text("Creative")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text("0.7 is a good balance.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var topKCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top-K")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            HStack {
                Text("Top-K")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(vm.topK)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Slider(value: Binding(
                get: { Double(vm.topK) },
                set: { vm.topK = Int($0) }
            ), in: 1...100, step: 1)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                Text("Focused")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Text("Diverse")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text("Number of top tokens to consider.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var topPCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top-P")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)

            HStack {
                Text("Top-P")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.2f", vm.topP))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Slider(value: $vm.topP, in: 0.0...1.0, step: 0.05)
                .tint(.white.opacity(0.5))

            HStack(spacing: 0) {
                Text("Narrow")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                Text("Broad")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Text("Nucleus sampling probability mass.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var resetButton: some View {
        Button {
            vm.resetSamplerDefaults()
        } label: {
            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, LamoTheme.Spacing.md)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }
}
