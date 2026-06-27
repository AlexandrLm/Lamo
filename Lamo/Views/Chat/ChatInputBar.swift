import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @State private var isFocused = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: LamoTheme.Spacing.sm) {
                // Attachment button
                Button(action: {}) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(LamoTheme.Colors.accent)
                }
                .padding(.bottom, 6)

                // Input field
                HStack(alignment: .bottom, spacing: LamoTheme.Spacing.xs) {
                    TextField("Message...", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .font(LamoTheme.Fonts.body)
                        .padding(.horizontal, LamoTheme.Spacing.md)
                        .padding(.vertical, 10)
                        .scrollContentBackground(.hidden)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input, style: .continuous)
                        .stroke(
                            isFocused ? LamoTheme.Colors.accent.opacity(0.5) : Color(uiColor: .separator),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )

                // Send / Stop button
                if isStreaming {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 32, height: 32)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: onSend) {
                        ZStack {
                            Circle()
                                .fill(canSend ? LamoTheme.Colors.accent : Color(uiColor: .systemGray5))
                                .frame(width: 32, height: 32)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(canSend ? .white : Color(uiColor: .placeholderText))
                        }
                    }
                    .disabled(!canSend)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                    .sensoryFeedback(.selection, trigger: canSend)
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.md)
            .padding(.vertical, LamoTheme.Spacing.sm + 2)
            .background(.ultraThinMaterial)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
