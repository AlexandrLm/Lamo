import SwiftUI

struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(LamoTheme.Colors.textSecondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, LamoTheme.Spacing.md)
        .padding(.vertical, LamoTheme.Spacing.sm)
        .background(LamoTheme.Colors.assistantBubble)
        .clipShape(Capsule())
        .onAppear {
            isAnimating = true
        }
    }
}
