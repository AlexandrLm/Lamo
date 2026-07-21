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
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "compress")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.7))
                }

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
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)

                // Dismiss
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }

            // Expanded summary
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Color.white.opacity(0.06).frame(height: 1).padding(.vertical, 8)

                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8))
                        Text("SUMMARY")
                            .font(.system(size: 8, design: .monospaced))
                    }
                    .foregroundStyle(.orange.opacity(0.4))

                    Text(summary)
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}
