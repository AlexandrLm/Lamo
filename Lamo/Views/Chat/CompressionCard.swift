import SwiftUI

/// Card shown when the model compresses conversation history into a summary.
struct CompressionCard: View {
    let oldCount: Int
    let summary: String
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ToolBadge(icon: "compress", tint: .orange, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Context Compressed")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(oldCount) messages summarized")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LamoTheme.Colors.fillSubtle))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse summary" : "Expand summary")

                // Dismiss
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(LamoTheme.Colors.fillSubtle))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            // Expanded summary
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ThinDivider().padding(.vertical, 8)

                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8))
                        Text("SUMMARY")
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .foregroundStyle(.orange)

                    Text(summary)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
