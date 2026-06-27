import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: LamoTheme.Spacing.sm) {
            TextField("Message...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, LamoTheme.Spacing.md)
                .padding(.vertical, LamoTheme.Spacing.sm)
                .background(LamoTheme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input))
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? LamoTheme.Colors.accent : LamoTheme.Colors.textSecondary)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
