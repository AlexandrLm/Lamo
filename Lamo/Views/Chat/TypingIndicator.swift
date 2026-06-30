import SwiftUI

struct TypingIndicator: View {
    @State private var animationPhase = 0.0
    @State private var showDots = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(LamoTheme.Colors.accent.opacity(0.6))
                        .frame(width: 7, height: 7)
                        .offset(y: showDots ? sin(animationPhase + Double(index) * 0.8) * 4 : 0)
                        .opacity(showDots ? 0.5 + 0.5 * abs(sin(animationPhase + Double(index) * 0.8)) : 0.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemFill))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )

            Spacer(minLength: 48)
        }
        .onAppear {
            showDots = true
            withAnimation(
                .linear(duration: 1.8)
                .repeatForever(autoreverses: false)
            ) {
                animationPhase = .pi * 2
            }
        }
    }
}
