import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: LamoTheme.Spacing.sm) {
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .bold()
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                .padding(.bottom, 6)

                HStack(alignment: .bottom, spacing: LamoTheme.Spacing.xs) {
                    TextField("Message...", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .font(LamoTheme.Fonts.body)
                        .padding(.horizontal, LamoTheme.Spacing.md)
                        .padding(.vertical, 8)
                }
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input))
                .overlay(
                    RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                )

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .padding(.bottom, 4)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canSend ? .white : Color(uiColor: .placeholderText))
                            .padding(8)
                            .background(canSend ? LamoTheme.Colors.accent : Color(uiColor: .systemGray5))
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                    .padding(.bottom, 4)
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.md)
            .padding(.vertical, LamoTheme.Spacing.sm + 2)
            .background(.ultraThinMaterial)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
