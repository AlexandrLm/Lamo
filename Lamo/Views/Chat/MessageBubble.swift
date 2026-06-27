import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LamoTheme.Spacing.xs) {
                MarkdownRenderer(
                    text: message.content,
                    textColor: message.role == .user ? LamoTheme.Colors.bubbleTextUser : LamoTheme.Colors.bubbleTextAssistant
                )
                .padding(.horizontal, LamoTheme.Spacing.md)
                .padding(.vertical, LamoTheme.Spacing.sm + 2)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isUser: message.role == .user))
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)

                if message.isStreaming {
                    TypingIndicator()
                        .padding(.horizontal, LamoTheme.Spacing.xs)
                }

                // Timestamp for completed messages
                if !message.isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(LamoTheme.Fonts.caption2)
                        .foregroundStyle(LamoTheme.Colors.textTertiary)
                        .padding(.horizontal, LamoTheme.Spacing.sm)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            ))

            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            LamoTheme.Colors.userBubble
        } else {
            LamoTheme.Colors.assistantBubble
        }
    }
}
