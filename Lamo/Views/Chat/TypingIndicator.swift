import SwiftUI

struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(LamoTheme.Colors.textSecondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isAnimating ? 1.0 : 0.3)
                    .opacity(isAnimating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm + 2)
        .background(LamoTheme.Colors.assistantBubble)
        .clipShape(Capsule())
        .onAppear {
            isAnimating = true
        }
    }
}
