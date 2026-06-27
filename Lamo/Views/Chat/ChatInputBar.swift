import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: LamoTheme.Spacing.sm) {
                TextField("Message...", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .scrollContentBackground(.hidden)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular, in: .circle)
                    }
                    .padding(.bottom, 2)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSend()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSend ? .white : Color(.tertiaryLabel))
                            .frame(width: 36, height: 36)
                            .background(canSend ? Color(.tintColor) : Color(.quaternarySystemFill), in: .circle)
                    }
                    .disabled(!canSend)
                    .padding(.bottom, 2)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: LamoTheme.maxContentWidth)
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.sm)
            .padding(.bottom, LamoTheme.Spacing.xs)
        }
        .background(.regularMaterial)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
