import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @State private var isFocused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: LamoTheme.Spacing.sm) {
                TextField("Message...", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .font(LamoTheme.Fonts.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                    )

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.primary)
                            .clipShape(Circle())
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
                            .foregroundStyle(canSend ? .white : Color(uiColor: .tertiaryLabel))
                            .frame(width: 36, height: 36)
                            .background(canSend ? LamoTheme.Colors.accent : Color(uiColor: .quaternarySystemFill))
                            .clipShape(Circle())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
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
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
