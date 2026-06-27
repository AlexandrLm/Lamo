import SwiftUI

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: LamoTheme.Spacing.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(LamoTheme.Colors.textSecondary)
                    .frame(width: 6, height: 6)
                    .offset(y: sin(phase + Double(index) * 0.8) * 3)
            }
        }
        .padding(LamoTheme.Spacing.sm)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
