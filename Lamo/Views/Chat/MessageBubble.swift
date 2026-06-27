import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 50) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LamoTheme.Spacing.xs) {
                MarkdownRenderer(
                    text: message.content,
                    textColor: message.role == .user ? LamoTheme.Colors.bubbleTextUser : LamoTheme.Colors.bubbleTextAssistant
                )
                .padding(.horizontal, LamoTheme.Spacing.md)
                .padding(.vertical, LamoTheme.Spacing.sm + 2)
                .background(bubbleBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: LamoTheme.CornerRadius.bubble,
                        bottomLeadingRadius: message.role == .user ? LamoTheme.CornerRadius.bubble : 4,
                        bottomTrailingRadius: message.role == .user ? 4 : LamoTheme.CornerRadius.bubble,
                        topTrailingRadius: LamoTheme.CornerRadius.bubble
                    )
                )

                if message.isStreaming {
                    TypingIndicator()
                        .padding(.horizontal, LamoTheme.Spacing.xs)
                }
            }

            if message.role == .assistant { Spacer(minLength: 50) }
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
