import SwiftUI

struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.tertiary)
                    .frame(width: 5, height: 5)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            isAnimating = true
        }
    }
}
