import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LamoTheme.Spacing.xs) {
                MarkdownRenderer(
                    text: message.content,
                    textColor: LamoTheme.Colors.textPrimary
                )
                .lineSpacing(4)
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.vertical, LamoTheme.Spacing.md)
                .background(bubbleBackground)
                .clipShape(
                    .rect(
                        topLeadingRadius: LamoTheme.CornerRadius.bubble,
                        bottomLeadingRadius: message.role == .user ? LamoTheme.CornerRadius.bubble : 4,
                        bottomTrailingRadius: message.role == .user ? 4 : LamoTheme.CornerRadius.bubble,
                        topTrailingRadius: LamoTheme.CornerRadius.bubble,
                        style: .continuous
                    )
                )

                if message.isStreaming {
                    TypingIndicator()
                        .padding(.horizontal, LamoTheme.Spacing.xs)
                }

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
