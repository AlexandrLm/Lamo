import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: LamoTheme.Spacing.xs) {
                MarkdownRenderer(text: message.content)
                    .padding(LamoTheme.Spacing.md)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.bubble))

                if message.isStreaming {
                    TypingIndicator()
                        .padding(.horizontal, LamoTheme.Spacing.xs)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
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
